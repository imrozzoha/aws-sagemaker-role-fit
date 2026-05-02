# aws-sagemaker-role-fit

A serverless role-fit scoring engine powered by AWS SageMaker. Paste a job description and get an instant semantic match score against a candidate profile — broken down by skill domain.

[![AWS](https://img.shields.io/badge/AWS-SageMaker-FF9900?style=flat&logo=amazon-aws)](https://aws.amazon.com/sagemaker/)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6-7B42BC?style=flat&logo=terraform)](https://terraform.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## How it works

```
POST /match  { "job_description": "..." }
        │
        ▼
Lambda (match_handler.py)
        │
        ├── SageMaker Serverless Endpoint
        │   sentence-transformers/all-MiniLM-L6-v2
        │   → embeds the job description
        │
        ├── S3: pre-computed profile embeddings (configurable domains)
        │
        └── Cosine similarity → match score per domain
                │
                ▼
        { "overall_match": 87, "domains": { ... } }
```

**No training data required** — zero-shot semantic similarity using a pre-trained sentence transformer.

---

## Architecture

| Component | Service |
|-----------|---------|
| Embedding model | SageMaker Serverless Inference — `all-MiniLM-L6-v2` via HuggingFace DLC |
| Scoring logic | AWS Lambda (Python 3.12) |
| API | Amazon API Gateway REST — `POST /match` |
| Profile embeddings | Amazon S3 (pre-computed, AES256 encrypted) |
| IaC | Terraform |
| CI/CD | GitHub Actions (OIDC, no stored credentials) |

**SageMaker Serverless Inference** — scales to zero between requests, no idle cost.

---

## Skill domains

Define your own domains in `scripts/compute_embeddings.py`. Each domain is a short text description of what that skill area covers — the embedder turns it into a vector for comparison.

Example (replace with your own):

| Domain key | What it covers |
|------------|---------------|
| `domain_1` | Your first skill area — e.g. cloud platforms, infrastructure |
| `domain_2` | Your second skill area — e.g. security, compliance |
| `domain_3` | Your third skill area — e.g. AI/ML, data |
| `domain_4` | Your fourth skill area — e.g. APIs, integration |

You can add or remove domains freely — the Lambda handler reads domain keys dynamically from the embeddings file in S3.

---

## Deploy

### Prerequisites
- AWS account with SageMaker access
- Terraform >= 1.6
- S3 + DynamoDB for Terraform state (update `backend.tf`)
- GitHub OIDC role with permissions for SageMaker, Lambda, API Gateway, S3, IAM, SSM

### 1 — Deploy infrastructure

```bash
cd infra
terraform init
terraform apply
```

### 2 — Compute and upload profile embeddings

```bash
pip install -r scripts/requirements.txt
python scripts/compute_embeddings.py <embeddings-bucket-name>
```

The bucket name is printed in Terraform outputs.

### 3 — Test the endpoint

```bash
curl -X POST $(terraform -chdir=infra output -raw api_endpoint) \
  -H "Content-Type: application/json" \
  -d '{"job_description": "Senior DevSecOps Engineer with AWS EKS and Terraform experience"}'
```

---

## API

### `POST /match`

**Request:**
```json
{ "job_description": "Your job description text here (max 3000 chars)" }
```

**Response:**
```json
{
  "overall_match": 87,
  "domains": {
    "domain_1": { "label": "Your first skill area",  "score": 92 },
    "domain_2": { "label": "Your second skill area", "score": 88 },
    "domain_3": { "label": "Your third skill area",  "score": 81 },
    "domain_4": { "label": "Your fourth skill area", "score": 85 }
  }
}
```

Domain keys and labels are driven by your `compute_embeddings.py` configuration — not hardcoded in the Lambda.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Author

**Imrozzoha Chowdhury** — Senior Staff DevSecOps & Platform Engineer
[imrozzoha.com](https://imrozzoha.com) · [LinkedIn](https://linkedin.com/in/imrozzoha-chowdhury)
