FROM node:22-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Build TypeScript
RUN npm run build:mcp && npm run build

# Expose port
EXPOSE 3000

# Start command
CMD ["npm", "start"]
