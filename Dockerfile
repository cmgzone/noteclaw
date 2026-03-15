FROM node:20-alpine

WORKDIR /app

# Cache-busting argument to force rebuild when needed
ARG CACHEBUST=1

# Copy backend package files
COPY backend/package*.json ./

# Install dependencies (use lockfile for reproducible builds)
RUN npm ci

# Copy backend source code
COPY backend/ .

# Build TypeScript
RUN npm run build

# Expose port
EXPOSE 3000

# Start command (uses 4GB memory limit)
CMD ["npm", "start"]
