"""
Run this script once after the SageMaker endpoint is deployed to pre-compute
profile embeddings and upload them to S3.

Usage:
    pip install sentence-transformers boto3
    python scripts/compute_embeddings.py <s3-bucket-name>

Example:
    python scripts/compute_embeddings.py my-role-fit-embeddings

Customisation:
    Edit the DOMAINS dict below to describe YOUR skill areas.
    Each domain needs a unique key, a human-readable label, and a text
    description of the skills/experience in that area. The richer the text,
    the better the semantic matching.
"""

import json
import sys
import boto3
from sentence_transformers import SentenceTransformer

MODEL_ID = "sentence-transformers/all-MiniLM-L6-v2"
S3_KEY   = "profile_embeddings.json"
REGION   = "ap-southeast-2"  # change to your AWS region

# ── Define your skill domains here ───────────────────────────────────────────
# Replace these examples with your own areas of expertise.
# Tip: use keyword-rich descriptions — the model matches semantically,
# so more detail gives better results.

DOMAINS = {
    "domain_1": {
        "label": "Your First Skill Domain",
        "text": """
        Replace this with keywords and phrases that describe your first area
        of expertise. Be specific — tool names, frameworks, methodologies,
        and technologies you have hands-on experience with.
        """,
    },
    "domain_2": {
        "label": "Your Second Skill Domain",
        "text": """
        Replace this with keywords and phrases for your second skill area.
        """,
    },
    "domain_3": {
        "label": "Your Third Skill Domain",
        "text": """
        Replace this with keywords and phrases for your third skill area.
        """,
    },
    "domain_4": {
        "label": "Your Fourth Skill Domain",
        "text": """
        Replace this with keywords and phrases for your fourth skill area.
        """,
    },
}


def main(bucket: str) -> None:
    print(f"Loading model {MODEL_ID}...")
    model = SentenceTransformer(MODEL_ID)

    result = {"domains": {}}
    for key, data in DOMAINS.items():
        print(f"  Embedding: {data['label']}")
        embedding = model.encode(data["text"].strip()).tolist()
        result["domains"][key] = {
            "label": data["label"],
            "embedding": embedding,
        }

    payload = json.dumps(result)

    with open("profile_embeddings.json", "w") as f:
        f.write(payload)
    print("Saved profile_embeddings.json locally")

    s3 = boto3.client("s3", region_name=REGION)
    s3.put_object(
        Bucket=bucket,
        Key=S3_KEY,
        Body=payload.encode(),
        ContentType="application/json",
    )
    print(f"Uploaded to s3://{bucket}/{S3_KEY}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python compute_embeddings.py <s3-bucket-name>")
        sys.exit(1)
    main(sys.argv[1])
