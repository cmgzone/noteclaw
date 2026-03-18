# Deploying Backend to Coolify

This guide details how to deploy the **NoteClaw Backend** to your self-hosted Coolify instance.

## Prerequisites

1.  **Git Repository**: Ensure this project is pushed to a Git repository (GitHub/GitLab/etc.) that your Coolify instance can access.
2.  **Coolify Instance**: You must have administrative access to your Coolify dashboard.
3.  **Neon Database**: Have your Neon database credentials ready.

## Deployment Steps

### 1. Create a New Service

1.  Log in to your Coolify dashboard.
2.  Navigate to your Project environment.
3.  Click **"+ New"** -> **"Application"** -> **"Public Repository"** (or Private if applicable).
4.  Paste your Git repository URL.
5.  Select the **Branch** you want to deploy (e.g., `main`).

### 2. Configure Service Settings

Once the repository is loaded, configure the following settings:

*   **Build Pack**: Select **Docker**.
*   **Docker Context**: Enter `/backend`. (This is crucial as the backend code lives in a subdirectory).
*   **Dockerfile Location**: Enter `/backend/Dockerfile`.
*   **Port**: `3000` (This matches the `EXPOSE 3000` in the Dockerfile).

### 3. Environment Variables

Navigate to the **Environment Variables** tab of your new service and add the following keys. **You must replace the placeholder values with your actual secrets.**

Important: in Coolify, each environment variable must be in `KEY=VALUE` form (one per line). Do not prefix lines with `-` or wrap values in backticks, otherwise the build container will treat them like shell commands and fail.

```env
# Server Configuration
PORT=3000
NODE_ENV=production

# Security
JWT_SECRET=generate-a-secure-random-string-here

# Neon Database (Required)
# Use the connection string format for simplicity, OR provide individual fields
DATABASE_URL=postgresql://user:password@host:5432/database?sslmode=require

# AI API Keys (At least one is required for AI features)
GEMINI_API_KEY=your-gemini-api-key
OPENROUTER_API_KEY=your-openrouter-api-key

# Search & content fetching (Required for Research features)
SERPER_API_KEY=your-serper-api-key

# Google Calendar OAuth (Optional)
GOOGLE_CALENDAR_CLIENT_ID=your-google-calendar-client-id
GOOGLE_CALENDAR_CLIENT_SECRET=your-google-calendar-client-secret
GOOGLE_CALENDAR_REDIRECT_URI=https://backend.taskiumnetwork.com/api/google-calendar/callback

# Optional Integrations (Add if you use them)
# Audio
ELEVENLABS_API_KEY=
DEEPGRAM_API_KEY=
ASSEMBLYAI_API_KEY=
MURF_API_KEY=

# Payments
STRIPE_PUBLISHABLE_KEY=
STRIPE_SECRET_KEY=

# Storage (Bunny.net)
BUNNY_STORAGE_ZONE=
BUNNY_STORAGE_API_KEY=
BUNNY_CDN_HOSTNAME=
BUNNY_STORAGE_HOSTNAME=
```

### 4. Deploy

1.  Click **"Save"** configuration.
2.  Click **"Deploy"**.
3.  Monitor the "Deployment Logs" to ensure the build completes successfully.

### 5. Verify Deployment

Once the deployment is "Healthy":
1.  Click on the **Links** or **URL** domain assigned by Coolify.
2.  Append `/health` to the URL (e.g., `https://api.your-domain.com/health`).
3.  You should see a JSON response: `{"status":"ok", ...}`.

## Troubleshooting

*   **Build Fails**: Check if you set the **Docker Context** directory correctly to `/backend`. The Dockerfile expects to be built from within that directory context to find `package.json`.
*   **Database Connection Failed**: Double-check your `DATABASE_URL` in the Environment Variables. Ensure Coolify allows outbound traffic to Neon (port 5432).
*   **Application Error**: Check the "Application Logs" in Coolify for startup errors.
*   **WebSockets Not Working (Offline/Connection Closed)**:
    *   If using Cloudflare Proxy, ensure WebSockets are enabled.
    *   **Symptom**: If you see `{"error":"Route not found","path":"/ws/agent"}` in the response, it means the request reached the backend but as **HTTP**, not WebSocket. The Proxy stripped the headers.
    *   **Coolify Proxy**: Ensure your proxy configuration forwards `Upgrade` and `Connection` headers. You may need to add custom Nginx configuration:
        ```nginx
        location /ws/ {
            proxy_pass http://host.docker.internal:3000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
        ```

## Next Steps

Once the backend is live, you can deploy the `web_app` and `admin_panel`.

### Deploying the Web App (Frontend)

1.  **Create Service**: Select your repository.
2.  **Configuration**:
    *   Base Directory: `/web_app`
    *   Dockerfile: `/Dockerfile`
    *   Port: `3000`
3.  **Environment Variables**:
    *   `NEXT_PUBLIC_API_URL`: Your backend URL (e.g., `https://api.your-domain.com/api`).

### Deploying the Admin Panel

1.  **Create Service**: Select your repository.
2.  **Configuration**:
    *   Base Directory: `/admin_panel`
    *   Dockerfile: `/Dockerfile`
    *   Port: `80` (Note: Nginx runs on port 80 internally).
3.  **Environment Variables**:
    *   `VITE_API_URL`: Your backend URL (e.g., `https://api.your-domain.com/api`).
    *   *Important*: Since this is a static build, if you change this variable later, you **MUST** trigger a full redeploy (Rebuild) for the changes to take effect.
