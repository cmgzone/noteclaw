import express from 'express';
import cors from 'cors';
import compression from 'compression';
import dotenv from 'dotenv';
import { createServer } from 'http';
import { parse } from 'url';

// Memory-bank surface
import authRoutes from './routes/auth.js';
import notebooksRoutes from './routes/notebooks.js';
import sourcesRoutes from './routes/sources.js';
import aiRoutes from './routes/ai.js';
import adminRoutes from './routes/admin.js';
import codingAgentRoutes from './routes/codingAgent.js';
import githubRoutes from './routes/github.js';
import mcpDownloadRoutes from './routes/mcpDownload.js';
import remoteMcpRoutes from './routes/remoteMcp.js';
import subscriptionRoutes from './routes/subscriptions.js';

import { agentWebSocketService } from './services/agentWebSocketService.js';
import { initializeDatabase } from './config/database.js';

// Load environment variables
dotenv.config();

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down gracefully...');
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('SIGINT received, shutting down gracefully...');
    process.exit(0);
});

const app = express();
const requestedPort = (() => {
    const raw = process.env.PORT;
    if (!raw) return 3000;
    const parsed = Number(raw);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 3000;
})();
const maxPortAttempts = 20;

// Middleware
app.use(compression());
app.use(cors({
    origin: true, // Allow all origins (reflects the request origin)
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: [
        'Content-Type',
        'Authorization',
        'X-Requested-With',
        'X-User-Api-Key',
        'Mcp-Session-Id',
        'MCP-Protocol-Version',
        'Last-Event-ID',
    ],
    exposedHeaders: ['Mcp-Session-Id'],
    credentials: true,
}));

// Handle preflight requests explicitly
app.options('*', cors());

app.use(express.json({
    limit: '100mb',
    verify: (req, _res, buffer) => {
        if (
            (req as express.Request).originalUrl
            === '/api/subscriptions/webhook/stripe'
        ) {
            (req as express.Request & { rawBody?: Buffer }).rawBody =
                Buffer.from(buffer);
        }
    },
}));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));



// Request logging middleware
app.use((req, res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
});

// Health check
const healthHandler = (req: express.Request, res: express.Response) => {
    res.json({
        status: 'ok',
        message: 'Backend is running',
        timestamp: new Date().toISOString(),
        version: '2.0.0'
    });
};

app.get('/health', healthHandler);
app.get('/api/health', healthHandler);
app.use('/mcp', remoteMcpRoutes);

// Memory-bank, account, subscription, and administration surfaces.
app.use('/api/auth', authRoutes);
app.use('/api/notebooks', notebooksRoutes);
app.use('/api/sources', sourcesRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/coding-agent', codingAgentRoutes);
app.use('/api/github', githubRoutes);
app.use('/api/mcp', mcpDownloadRoutes);
app.use('/api/subscriptions', subscriptionRoutes);
// 404 handler
app.use((req, res) => {
    console.log(`[404] Route not found: ${req.method} ${req.path}`);
    res.status(404).json({ error: 'Route not found', path: req.path });
});

// Error handler
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
    console.error('Error:', err);
    res.status(500).json({
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
});

// Start server with WebSocket support
const server = createServer(app);

// Initialize WebSocket service for real-time agent communication
agentWebSocketService.initialize(server);

let activePort = requestedPort;
let portAttempts = 0;
let isStartingServer = false;

const startListening = () => {
    if (isStartingServer || server.listening) {
        return;
    }

    isStartingServer = true;

    // Add debugging for WebSocket upgrades
    server.on('upgrade', (req, socket, head) => {
        const url = parse(req.url || '').pathname || '';
        console.log(`[WS UPGRADE] Request for ${url}`);

        if (url.startsWith('/ws/')) {
            // Let the other specialized handlers deal with it if they are still using auto-attach
            // Note: We should eventually migrate all to manual for consistency
            return;
        }

        console.log(`[WS UPGRADE] Unhandled path: ${url}`);
    });

    server.listen(activePort, () => {
        isStartingServer = false;
        console.log(`🚀 Server is running on http://localhost:${activePort}`);
        console.log(`🔌 WebSocket available at ws://localhost:${activePort}/ws/agent`);
        console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
        console.log(`📅 Started at: ${new Date().toISOString()}`);
    });
};

server.on('error', (err: any) => {
    isStartingServer = false;
    if (err?.code === 'EADDRINUSE' && portAttempts < maxPortAttempts) {
        const currentPort = activePort;
        activePort = currentPort + 1;
        portAttempts += 1;
        console.error(`Port ${currentPort} is already in use. Trying ${activePort}...`);
        setTimeout(() => startListening(), 250);
        return;
    }

    console.error('Server failed to start:', err);
    process.exit(1);
});

async function bootstrap() {
    await initializeDatabase();
    startListening();
}

if (process.env.NODE_ENV !== 'test') {
    bootstrap().catch((error) => {
        console.error('Application bootstrap failed:', error);
        process.exit(1);
    });
}

export default app;
