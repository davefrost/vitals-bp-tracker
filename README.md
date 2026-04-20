# Vitals — Blood Pressure Tracker

A self-hosted, multi-user blood pressure tracker. Deployable locally with Docker Compose or to Google Cloud Run + Cloud SQL.

## Project structure

```
bp-tracker/
├── server/          Node.js + Express API (TypeScript, compiled with esbuild)
├── client/          React SPA (TypeScript, built with Vite)
├── Dockerfile       Single image — serves both API and frontend
├── docker-compose.yml  Local development
├── cloudbuild.yaml  Google Cloud Build + Cloud Run deployment
└── .env.example     Required environment variables
```

---

## Running locally with Docker Compose

```bash
# 1. Create a .env file with your JWT secret
cp .env.example .env
echo "JWT_SECRET=$(openssl rand -hex 32)" >> .env

# 2. Build and start
docker compose up -d --build

# 3. Open http://localhost:3000
```

---

## Deploying to Google Cloud Run

### One-time setup

**1. Create a Cloud SQL PostgreSQL instance**

```bash
gcloud sql instances create bp-tracker-db \
  --database-version=POSTGRES_16 \
  --tier=db-f1-micro \
  --region=europe-west2 \
  --storage-type=SSD \
  --storage-size=10GB

gcloud sql databases create bptracker --instance=bp-tracker-db
gcloud sql users create bptracker --instance=bp-tracker-db --password=CHOOSE_A_PASSWORD
```

**2. Create an Artifact Registry repository**

```bash
gcloud artifacts repositories create bp-tracker \
  --repository-format=docker \
  --location=europe-west2
```

**3. Store secrets in Secret Manager**

```bash
# Database URL — use Cloud SQL socket format for Cloud Run
echo -n "postgresql://bptracker:YOUR_DB_PASSWORD@/bptracker?host=/cloudsql/YOUR_PROJECT:europe-west2:bp-tracker-db" \
  | gcloud secrets create bp-tracker-db-url --data-file=-

# JWT secret
openssl rand -hex 32 \
  | gcloud secrets create bp-tracker-jwt-secret --data-file=-
```

**4. Grant Cloud Run access to the secrets and Cloud SQL**

```bash
# Get the Cloud Run service account
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding bp-tracker-db-url \
  --member="serviceAccount:${SERVICE_ACCOUNT}" --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding bp-tracker-jwt-secret \
  --member="serviceAccount:${SERVICE_ACCOUNT}" --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT}" --role="roles/cloudsql.client"
```

### Deploying

**Option A — Cloud Build (CI/CD, recommended)**

Connect your repository in the Google Cloud Console under Cloud Build → Triggers, point it at `cloudbuild.yaml`, and every push to `main` will build, push, and deploy automatically.

**Option B — Manual from your local machine**

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Build and push
docker build -t europe-west2-docker.pkg.dev/$PROJECT_ID/bp-tracker/app:latest .
docker push europe-west2-docker.pkg.dev/$PROJECT_ID/bp-tracker/app:latest

# Deploy
gcloud run deploy bp-tracker \
  --image=europe-west2-docker.pkg.dev/$PROJECT_ID/bp-tracker/app:latest \
  --platform=managed \
  --region=europe-west2 \
  --allow-unauthenticated \
  --port=8080 \
  --add-cloudsql-instances=YOUR_PROJECT:europe-west2:bp-tracker-db \
  --set-env-vars=PORT=8080,NODE_ENV=production \
  --set-secrets=DATABASE_URL=bp-tracker-db-url:latest,JWT_SECRET=bp-tracker-jwt-secret:latest
```

### Important: Cloud Run uses port 8080

Cloud Run routes traffic to port 8080 by default. The `cloudbuild.yaml` and deploy command above already set `PORT=8080`. Your Dockerfile's `EXPOSE 3000` is just documentation — the actual port is set by the `PORT` environment variable at runtime.

---

## Migrating existing data from the old monorepo version

If you have readings in an existing database, they will have a null `user_id`. After deploying and registering an account, you can associate them via psql:

```sql
-- Find your user ID
SELECT id, username FROM users;

-- Attach old readings to your account
UPDATE readings SET user_id = <your_id> WHERE user_id IS NULL;
```

---

## Environment variables

| Variable       | Required | Description                                      |
|----------------|----------|--------------------------------------------------|
| `PORT`         | Yes      | Port the server listens on (use 8080 on Cloud Run) |
| `DATABASE_URL` | Yes      | PostgreSQL connection string                     |
| `JWT_SECRET`   | Yes      | Secret for signing auth tokens — keep this safe  |
| `NODE_ENV`     | No       | `production` disables pino-pretty logging        |
| `LOG_LEVEL`    | No       | `info` (default), `debug`, `warn`, `error`       |
