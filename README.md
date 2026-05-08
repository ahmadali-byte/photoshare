# PhotoShare — Scalable Cloud-Native Photo Platform

**COM769 Scalable Advanced Software Solutions — Coursework 2**
MSc Computer Science | Ulster University (QAHE)

---

## Overview

PhotoShare is an Instagram-like photo-sharing web application built on **Azure cloud-native services**. It demonstrates scalable architecture, serverless computing, AI integration, and modern DevOps practices.

**Live App:** `https://<your-static-web-app>.azurestaticapps.net`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Static Web Apps                     │
│              (HTML + CSS + JS — Global CDN)                  │
└──────────────────────┬──────────────────────────────────────┘
                       │ REST API (HTTPS)
┌──────────────────────▼──────────────────────────────────────┐
│              Azure Functions (Serverless Python)             │
│   /api/auth/*  /api/photos/*  /api/comments  /api/ratings   │
└──────┬───────────┬───────────────┬────────────┬─────────────┘
       │           │               │            │
  ┌────▼────┐ ┌───▼──────┐ ┌─────▼────┐ ┌────▼──────────┐
  │Cosmos DB│ │  Azure   │ │ Computer │ │Text Analytics │
  │(NoSQL)  │ │  Blob    │ │ Vision   │ │(Sentiment AI) │
  │users    │ │ Storage  │ │  API     │ │               │
  │photos   │ │ (photos) │ │ (tags +  │ │(comment mood) │
  │comments │ │          │ │ caption) │ │               │
  │ratings  │ └──────────┘ └──────────┘ └───────────────┘
  └─────────┘
```

---

## Features

### Core Functionality
| Feature | Description |
|---------|-------------|
| Creator accounts | Upload photos with title, caption, location, people |
| Consumer accounts | Browse, search, comment, and rate photos |
| Role-based access | JWT-based auth; creators and consumers have separate views |
| Photo search | Full-text search across title, caption, location, creator |
| Ratings | 1-5 star rating system with live average calculation |

### Advanced Features (Distinction Level)
| # | Feature | Azure Service |
|---|---------|--------------|
| 1 | **Computer Vision AI** | Azure AI Vision — auto-tags and captions every uploaded photo |
| 2 | **Sentiment Analysis** | Azure Text Analytics — classifies comments as positive/negative/neutral |
| 3 | **Serverless Architecture** | Azure Functions (Consumption plan) — scales to zero, pay-per-execution |
| 4 | **CI/CD Pipeline** | GitHub Actions — automated test, lint, and deploy on every push |

---

## Project Structure

```
photoshare/
├── .github/workflows/deploy.yml    # CI/CD pipeline
├── backend/
│   ├── function_app.py             # All REST API endpoints
│   ├── requirements.txt
│   ├── host.json
│   ├── tests/
│   │   └── test_auth_utils.py      # Unit tests
│   └── utils/
│       ├── auth_utils.py           # JWT + bcrypt auth
│       ├── cosmos_db.py            # Database operations
│       ├── blob_storage.py         # Photo storage
│       └── cognitive.py            # AI services
├── frontend/
│   ├── index.html                  # Login / Register
│   ├── creator.html                # Creator studio
│   ├── consumer.html               # Consumer feed
│   ├── css/app.css
│   ├── js/
│   │   ├── config.js               # API base URL
│   │   ├── auth.js                 # Shared auth + utilities
│   │   ├── creator.js              # Creator page logic
│   │   └── consumer.js             # Consumer page logic
│   └── staticwebapp.config.json
└── infrastructure/
    ├── main.bicep                  # All Azure resources as code
    ├── parameters.json
    └── deploy.sh                   # One-command deployment script
```

---

## Azure Services Used

| Service | Purpose | Tier |
|---------|---------|------|
| Azure Static Web Apps | Frontend hosting + Global CDN | Free |
| Azure Functions | Serverless REST API (Python) | Consumption (Free) |
| Azure Cosmos DB | NoSQL database (users, photos, comments, ratings) | Free tier (serverless) |
| Azure Blob Storage | Photo file storage | LRS (low cost) |
| Azure AI Vision | Computer Vision — image analysis | F0 (Free) |
| Azure Language Service | Text Analytics — sentiment analysis | F0 (Free) |
| Azure Application Insights | Monitoring and telemetry | Free |

---

## REST API Endpoints

### Authentication
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/api/auth/register` | Register consumer account | No |
| POST | `/api/auth/login` | Login (any role) | No |
| POST | `/api/auth/create-creator` | Create creator account | Admin Secret |

### Photos
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET | `/api/photos` | Get photo feed (paginated) | No |
| POST | `/api/photos` | Upload photo + AI analysis | Creator |
| GET | `/api/photos/{id}` | Get single photo | No |
| DELETE | `/api/photos/{id}` | Delete photo | Creator (owner) |
| GET | `/api/photos/search?q=` | Search photos | No |
| GET | `/api/photos/my` | Get own photos | Creator |

### Social
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET | `/api/photos/{id}/comments` | Get comments | No |
| POST | `/api/photos/{id}/comments` | Add comment + sentiment | Any user |
| POST | `/api/photos/{id}/rate` | Rate photo (1-5) | Any user |

### System
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |

---

## Setup & Deployment

### Prerequisites
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure Functions Core Tools v4](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local)
- Python 3.11+
- GitHub account

### Option A: Automated Deployment (Recommended)
```bash
cd infrastructure
./deploy.sh
```

### Option B: Manual Step-by-Step

#### 1. Login to Azure
```bash
az login --use-device-code
```

#### 2. Create Resource Group
```bash
az group create --name photoshare-rg --location uksouth
```

#### 3. Deploy Infrastructure
```bash
az deployment group create \
  --resource-group photoshare-rg \
  --template-file infrastructure/main.bicep \
  --parameters @infrastructure/parameters.json \
  --parameters jwtSecret="your-long-secret" adminSecret="your-admin-secret"
```

#### 4. Deploy Backend
```bash
cd backend
pip install -r requirements.txt --target=".python_packages/lib/site-packages"
func azure functionapp publish <function-app-name> --python
```

#### 5. Update Frontend Config
Edit `frontend/js/config.js`:
```js
const API_BASE = "https://<your-function-app>.azurewebsites.net";
```

#### 6. Deploy Frontend
```bash
# Via Azure Static Web Apps CLI or GitHub Actions
```

### Create a Creator Account
Creator accounts cannot be self-registered. Use this admin endpoint:
```bash
curl -X POST https://<function-app-url>/api/auth/create-creator \
  -H "Content-Type: application/json" \
  -H "X-Admin-Secret: <your-admin-secret>" \
  -d '{"username": "creator1", "email": "creator@example.com", "password": "SecurePass123"}'
```

---

## CI/CD Pipeline

GitHub Actions workflow triggers on every push to `main`:

1. **Test** — Runs Python unit tests + flake8 linting
2. **Deploy Backend** — Publishes to Azure Functions
3. **Deploy Frontend** — Injects API URL + deploys to Azure Static Web Apps
4. **Validate Bicep** — Validates infrastructure template

### GitHub Secrets Required
| Secret | Value |
|--------|-------|
| `FUNCTION_APP_NAME` | Your Azure Function App name |
| `FUNCTION_APP_URL` | `https://<name>.azurewebsites.net` |
| `AZURE_FUNCTIONAPP_PUBLISH_PROFILE` | Download from Azure Portal |
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | From Static Web App → Manage token |
| `AZURE_CREDENTIALS` | Output of `az ad sp create-for-rbac` |

---

## Running Tests Locally

```bash
cd backend
pip install -r requirements.txt pytest pytest-cov
pytest tests/ -v
```

---

## Scalability Design

- **Serverless Functions** — Automatically scales from 0 to thousands of concurrent instances
- **Cosmos DB Serverless** — Scales throughput on demand, no provisioned capacity needed
- **Azure Static Web Apps** — Content delivered via global Azure CDN
- **Blob Storage** — Geo-redundant, petabyte-scale object storage
- **Stateless API** — JWT tokens mean any function instance can handle any request
- **Connection pooling** — Cosmos and Blob clients reused across warm function invocations

---

## Limitations & Future Work

- Creator enrolment requires admin API call (by design — no public creator self-signup)
- Free tier Cognitive Services: 20 transactions/minute (sufficient for demo)
- Cosmos DB free tier: single account per subscription
- No image resizing/thumbnail generation (would add Azure Media Services)
- No real-time notifications (would add Azure SignalR Service)

---

*Built with Azure cloud-native services for COM769 — Scalable Advanced Software Solutions*
