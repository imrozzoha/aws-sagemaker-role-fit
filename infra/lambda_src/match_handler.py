import json
import math
import os
import boto3

sagemaker_runtime = boto3.client("sagemaker-runtime")
s3 = boto3.client("s3")

SAGEMAKER_ENDPOINT = os.environ["SAGEMAKER_ENDPOINT"]
EMBEDDINGS_BUCKET  = os.environ["EMBEDDINGS_BUCKET"]
EMBEDDINGS_KEY     = os.environ["EMBEDDINGS_KEY"]
CORS_ORIGIN        = os.environ.get("CORS_ORIGIN", "*")
MAX_INPUT_CHARS    = 8000   # allow full JDs; chunking handles the token limit
CHUNK_SIZE         = 1400   # ~400 tokens per chunk, safely under 512-token model limit
CHUNK_OVERLAP      = 150    # character overlap so boundary context isn't lost
MAX_CHUNKS         = 5      # cap to bound latency on warm calls

_profile_embeddings = None


def _load_profile_embeddings():
    global _profile_embeddings
    if _profile_embeddings is None:
        resp = s3.get_object(Bucket=EMBEDDINGS_BUCKET, Key=EMBEDDINGS_KEY)
        _profile_embeddings = json.loads(resp["Body"].read())
    return _profile_embeddings


def _chunk_text(text: str) -> list:
    """Split text into overlapping chunks at word boundaries."""
    if len(text) <= CHUNK_SIZE:
        return [text]
    chunks = []
    start = 0
    while start < len(text) and len(chunks) < MAX_CHUNKS:
        end = min(start + CHUNK_SIZE, len(text))
        if end < len(text):
            boundary = text.rfind(' ', start, end)
            if boundary > start:
                end = boundary
        chunks.append(text[start:end].strip())
        start = end - CHUNK_OVERLAP
    return chunks


def _embed_chunk(text: str) -> list:
    payload = json.dumps({"inputs": text, "parameters": {"truncation": True}})
    resp = sagemaker_runtime.invoke_endpoint(
        EndpointName=SAGEMAKER_ENDPOINT,
        ContentType="application/json",
        Body=payload,
    )
    result = json.loads(resp["Body"].read())
    # feature-extraction returns [batch][seq_len][hidden] — mean pool over seq_len
    # some sentence-transformer builds return [batch][hidden] directly
    if isinstance(result[0][0], list):
        return _mean_pool(result[0])
    return result[0]


def _get_embedding(text: str) -> list:
    """Embed full text by chunking, embedding each chunk, and averaging."""
    chunks = _chunk_text(text)
    vectors = [_embed_chunk(c) for c in chunks]
    if len(vectors) == 1:
        return vectors[0]
    dim = len(vectors[0])
    return [sum(v[j] for v in vectors) / len(vectors) for j in range(dim)]


def _mean_pool(token_embeddings: list) -> list:
    n = len(token_embeddings)
    dim = len(token_embeddings[0])
    return [sum(token_embeddings[i][j] for i in range(n)) / n for j in range(dim)]


def _cosine_similarity(a: list, b: list) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    mag_a = math.sqrt(sum(x * x for x in a))
    mag_b = math.sqrt(sum(x * x for x in b))
    if mag_a == 0 or mag_b == 0:
        return 0.0
    return dot / (mag_a * mag_b)


def _cors_headers() -> dict:
    return {
        "Access-Control-Allow-Origin":  CORS_ORIGIN,
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "POST,OPTIONS",
        "Content-Type": "application/json",
    }


def handler(event: dict, context) -> dict:
    if event.get("httpMethod") == "OPTIONS":
        return {"statusCode": 200, "headers": _cors_headers(), "body": ""}

    try:
        body = json.loads(event.get("body") or "{}")
        jd_text = body.get("job_description", "").strip()[:MAX_INPUT_CHARS]

        if not jd_text:
            return {
                "statusCode": 400,
                "headers": _cors_headers(),
                "body": json.dumps({"error": "job_description is required"}),
            }

        jd_embedding = _get_embedding(jd_text)
        profile = _load_profile_embeddings()

        domains = {}
        for key, data in profile["domains"].items():
            sim = _cosine_similarity(jd_embedding, data["embedding"])
            domains[key] = {
                "label": data["label"],
                "score": max(0, min(100, round(sim * 130))),
            }

        overall = round(sum(d["score"] for d in domains.values()) / len(domains))

        return {
            "statusCode": 200,
            "headers": _cors_headers(),
            "body": json.dumps({"overall_match": overall, "domains": domains}),
        }

    except Exception as exc:
        return {
            "statusCode": 500,
            "headers": _cors_headers(),
            "body": json.dumps({"error": str(exc)}),
        }
