# NoteClaw Backend Deployment Guide

This guide covers deploying the NoteClaw backend to various platforms including GitHub Container Registry, Render, Railway, and self-hosted environments.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- GitHub account with repository access
- Node.js 20+ for local development

### Environment Setup

1. **Copy environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Configure your environment variables:**
   - Database connection string
   - JWT secret
   - API keys for AI services
   - Payment provider keys
   - GitHub OAuth credentials

## Deployment Options

### 1. GitHub Actions (Recommended)

The repository includes automated CI/CD with GitHub Actions that:
- Runs tests and linting
- Builds Docker images
- Pushes to GitHub Container Registry
- Deploys to staging and production
- Performs security scans

**Setup:**
1. Enable GitHub Actions in your repository
2. Configure environment secrets in GitHub Settings > Secrets and variables > Actions
3. Push to main branch to trigger deployment

**Required Secrets:**
```
DATABASE_URL
JWT_SECRET
STRIPE_SECRET_KEY
OPENAI_API_KEY
GEMINI_API_KEY
ELEVENLABS_API_KEY
DEEPGRAM_API_KEY
SERPER_API_KEY
GITHUB_CLIENT_ID
GITHUB_CLIENT_SECRET
```

### 2. Render (One-Click Deploy)

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy)

**Manual Setup:**
1. Fork this repository
2. Connect your GitHub account to Render
3. Create a new Web Service from your fork
4. Use the `render.yaml` configuration
5. Set environment variables in Render dashboard

### 3. Railway

**One-Click Deploy:**
[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/your-template-id)

**Manual Setup:**
1. Install Railway CLI: `npm install -g @railway/cli`
2. Login: `railway login`
3. Deploy: `railway up`
4. Set environment variables: `railway variables set KEY=value`

### 4. Docker Compose (Self-Hosted)

**Quick Deploy:**
```bash
# Clone repository
git clone https://github.com/cmgzone/notebookllm.git
cd notebookllm/backend

# Copy and configure environment
cp deploy/production.env .env.production
# Edit .env.production with your values

# Deploy
cd deploy
chmod +x deploy.sh
./deploy.sh production
```

**Windows:**
```powershell
# Deploy using PowerShell script
cd deploy
.\deploy.ps1 -Environment production
```

### 5. Manual Docker Deployment

```bash
# Build image
docker build -t notebookllm-backend .

# Run with environment file
docker run -d \
  --name notebookllm-backend \
  --env-file .env.production \
  -p 3000:3000 \
  notebookllm-backend
```

## Environment Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `NODE_ENV` | Environment mode | `production` |
| `PORT` | Server port | `3000` |
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://user:pass@host:5432/db` |
| `JWT_SECRET` | JWT signing secret | `your-secret-key` |
| `REDIS_URL` | Redis connection string | `redis://localhost:6379` |

### AI Service Keys

| Variable | Service | Required |
|----------|---------|----------|
| `OPENAI_API_KEY` | OpenAI GPT models | Yes |
| `GEMINI_API_KEY` | Google Gemini | Yes |
| `ELEVENLABS_API_KEY` | Voice synthesis | Optional |
| `DEEPGRAM_API_KEY` | Speech-to-text | Optional |
| `SERPER_API_KEY` | Web search | Optional |

### Payment & OAuth

| Variable | Service | Required |
|----------|---------|----------|
| `STRIPE_SECRET_KEY` | Stripe payments | Yes |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhooks | Yes |
| `GITHUB_CLIENT_ID` | GitHub OAuth | Optional |
| `GITHUB_CLIENT_SECRET` | GitHub OAuth | Optional |

## Database Setup

### PostgreSQL (Recommended)

1. **Create database:**
   ```sql
   CREATE DATABASE notebookllm;
   CREATE USER notebookllm_user WITH PASSWORD 'your_password';
   GRANT ALL PRIVILEGES ON DATABASE notebookllm TO notebookllm_user;
   ```

2. **Run migrations:**
   ```bash
   npm run migrate
   ```

### Neon (Serverless PostgreSQL)

1. Create account at [neon.tech](https://neon.tech)
2. Create new project
3. Copy connection string to `DATABASE_URL`
4. Run migrations

## Redis Setup

### Local Redis
```bash
# Install Redis
# Ubuntu/Debian
sudo apt install redis-server

# macOS
brew install redis

# Start Redis
redis-server
```

### Redis Cloud
1. Create account at [Redis Cloud](https://redis.com/try-free/)
2. Create database
3. Copy connection string to `REDIS_URL`

## Health Checks

The backend includes health check endpoints:

- `GET /health` - Basic health check
- `GET /health/detailed` - Detailed system status

Example response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-20T10:30:00Z",
  "services": {
    "database": "connected",
    "redis": "connected",
    "ai_services": "operational"
  }
}
```

## Monitoring & Logging

### Application Logs

Logs are structured JSON format:
```json
{
  "level": "info",
  "message": "Server started",
  "timestamp": "2024-01-20T10:30:00Z",
  "service": "backend",
  "version": "2.0.0"
}
```

### Metrics Endpoints

- `GET /metrics` - Prometheus metrics
- `GET /stats` - Application statistics

### Error Tracking

Configure error tracking service:
```env
SENTRY_DSN=your_sentry_dsn
ERROR_REPORTING=enabled
```

## Security

### SSL/TLS

Always use HTTPS in production:
```env
FORCE_HTTPS=true
SECURE_COOKIES=true
```

### CORS Configuration

Configure allowed origins:
```env
CORS_ORIGIN=https://yourapp.com,https://www.yourapp.com
```

### Rate Limiting

Built-in rate limiting:
```env
RATE_LIMIT_WINDOW_MS=900000  # 15 minutes
RATE_LIMIT_MAX_REQUESTS=100  # per window
```

## Scaling

### Horizontal Scaling

The backend is stateless and can be scaled horizontally:

```yaml
# docker-compose.scale.yml
version: '3.8'
services:
  backend:
    # ... configuration
    deploy:
      replicas: 3
  
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
```

### Load Balancer Configuration

Example Nginx configuration:
```nginx
upstream backend {
    server backend_1:3000;
    server backend_2:3000;
    server backend_3:3000;
}

server {
    listen 80;
    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Troubleshooting

### Common Issues

1. **Database Connection Failed**
   ```bash
   # Check database connectivity
   docker-compose exec backend npm run db:check
   ```

2. **Redis Connection Failed**
   ```bash
   # Check Redis connectivity
   docker-compose exec backend npm run redis:check
   ```

3. **High Memory Usage**
   ```bash
   # Increase Node.js memory limit
   export NODE_OPTIONS="--max-old-space-size=6144"
   ```

### Debug Mode

Enable debug logging:
```env
LOG_LEVEL=debug
DEBUG=notebookllm:*
```

### Performance Monitoring

Monitor key metrics:
- Response time
- Memory usage
- Database query performance
- Redis hit rate
- Error rate

## Backup & Recovery

### Database Backup

```bash
# Create backup
pg_dump $DATABASE_URL > backup.sql

# Restore backup
psql $DATABASE_URL < backup.sql
```

### Automated Backups

Set up automated backups:
```bash
# Add to crontab
0 2 * * * pg_dump $DATABASE_URL | gzip > /backups/db-$(date +\%Y\%m\%d).sql.gz
```

## Support

For deployment issues:
1. Check the [troubleshooting section](#troubleshooting)
2. Review application logs
3. Check health endpoints
4. Create an issue on GitHub

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development and deployment contribution guidelines.