# PhotoShare — Scalable Cloud-Native Photo Platform

**COM769 Scalable Advanced Software Solutions — Coursework 2**
Student: Ahmad Ali | B01048812
MSc Computer Science | Ulster University QAHE | May 2026

---

## Live Application

**Frontend:** https://psharestordivuk3vvdpnlm.z1.web.core.windows.net/
**Backend API:** https://pshare-func-divuk3vvdpnlm.azurewebsites.net/api/

---

## Overview

PhotoShare is an Instagram-like photo-sharing web application built entirely on Microsoft Azure cloud-native services. It demonstrates scalable serverless architecture, AI integration, role-based authentication, and automated CI/CD.

---

## Architecture

```
Browser
   │
   ▼
Azure Blob Storage (Static Website)
   │  HTML / CSS / JS
   │
   │ REST API calls (HTTPS)
   ▼
Azure Functions Python v2 — 10 Endpoints
   │
   ├── Cosmos DB          (users, photos, comments, ratings)
   ├── Blob Storage       (photo files)
   ├── Computer Vision    (AI tags + description on upload)
   └── Text Analytics     (sentiment analysis on comments)

GitHub Actions → automated test, build, deploy on every push
```

---

## Features

| Feature | Description |
|---------|-------------|
| Creator accounts | Upload photos with title, caption, location, people tagged |
| Consumer accounts | Browse, search, comment, and rate photos |
| JWT authentication | Role-based access — creators and consumers have separate views |
| Photo search | Search across title, location, AI tags, people |
| Star ratings | 1–5 star rating with live average |
| AI image analysis | Azure Computer Vision auto-tags every photo |
| Sentiment analysis | Azure Text Analytics scores every comment |
| CI/CD pipeline | GitHub Actions — auto deploy on every push to main |

---

## Azure Services

| Service | Purpose |
|---------|---------|
| Azure Functions (Python v2) | Serverless REST API — 10 endpoints |
| Azure Cosmos DB | NoSQL database |
| Azure Blob Storage | Photo file storage + static website hosting |
| Azure AI Vision | Computer Vision — image analysis |
| Azure Language Service | Text Analytics — sentiment analysis |
| Azure Application Insights | Monitoring |

---

## API Endpoints

| Method | Endpoint | Auth |
|--------|----------|------|
| POST | `/api/auth/register` | No |
| POST | `/api/auth/login` | No |
| GET | `/api/photos` | No |
| POST | `/api/photos` | Creator |
| GET | `/api/photos/search` | No |
| GET | `/api/photos/my` | Creator |
| GET/DELETE | `/api/photos/{id}` | No / Creator |
| GET/POST | `/api/photos/{id}/comments` | No / Any user |
| POST | `/api/photos/{id}/rate` | Any user |
| GET | `/api/health` | No |

---

## Project Structure

```
photoshare/
├── .github/workflows/deploy.yml    # CI/CD pipeline
├── backend/
│   ├── function_app.py             # All 10 REST API endpoints
│   ├── requirements.txt
│   ├── host.json
│   ├── tests/
│   │   └── test_auth_utils.py
│   └── utils/
│       ├── auth_utils.py           # JWT + bcrypt
│       ├── cosmos_db.py            # Database operations
│       ├── blob_storage.py         # Photo storage
│       └── cognitive.py            # Azure AI services
├── frontend/
│   ├── index.html                  # Landing page
│   ├── login.html                  # Sign in / Register
│   ├── creator.html                # Creator studio
│   ├── consumer.html               # Consumer feed
│   ├── css/app.css
│   └── js/
│       ├── config.js
│       ├── auth.js
│       ├── creator.js
│       └── consumer.js
└── infrastructure/
    ├── main.bicep                  # Azure infrastructure as code
    ├── parameters.json
    └── deploy.sh
```

---

## CI/CD Pipeline

GitHub Actions triggers on every push to `main`:
1. Run pytest unit tests + flake8 linting
2. Deploy backend to Azure Functions (Oryx remote build)
3. Deploy frontend to Azure Blob Storage $web container

---

## Scalability

- **Azure Functions** — scales to zero, pay-per-execution, no idle cost
- **Cosmos DB Serverless** — auto-scales throughput on demand
- **Blob Storage** — virtually unlimited, geo-redundant storage
- **Stateless API** — JWT means any instance handles any request
- **Static Frontend** — served directly from Blob, no server needed
