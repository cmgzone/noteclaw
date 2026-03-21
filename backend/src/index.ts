import express from 'express';
import cors from 'cors';
import compression from 'compression';
import dotenv from 'dotenv';
import { createServer } from 'http';
import { parse } from 'url';

// Import all routes
import authRoutes from './routes/auth.js';
import notebooksRoutes from './routes/notebooks.js';
import sourcesRoutes from './routes/sources.js';
import chunksRoutes from './routes/chunks.js';
import tagsRoutes from './routes/tags.js';
import aiRoutes from './routes/ai.js';
import subscriptionsRoutes from './routes/subscriptions.js';
import adminRoutes from './routes/admin.js';
import analyticsRoutes from './routes/analytics.js';
import mediaRoutes from './routes/media.js';
import sharingRoutes from './routes/sharing.js';
import recommendationsRoutes from './routes/recommendations.js';
import gamificationRoutes from './routes/gamification.js';
import studyRoutes from './routes/study.js';
import ebookRoutes from './routes/ebooks.js';
import researchRoutes from './routes/research.js';
import searchRoutes from './routes/search.js';
import featuresRoutes from './routes/features.js';
import voiceRoutes from './routes/voice.js';
import sportsRoutes from './routes/sports.js';
import codingAgentRoutes from './routes/codingAgent.js';
import mcpDownloadRoutes from './routes/mcpDownload.js';
import githubRoutes from './routes/github.js';
import planningRoutes from './routes/planning.js';
import socialRoutes from './routes/social.js';
import socialSharingRoutes from './routes/socialSharing.js';
import messagingRoutes from './routes/messaging.js';
import notificationsRoutes from './routes/notifications.js';
import googleDriveRoutes from './routes/googleDrive.js';
import contentRoutes from './routes/content.js';
import deepResearchRoutes from './routes/deepResearch.js';
import ragRoutes from './routes/rag.js';
import agentSkillsRoutes from './routes/agentSkills.js';
import publicPagesRoutes from './routes/publicPages.js';

// Import services
import bunnyService from './services/bunnyService.js';
import codeVerificationService from './services/codeVerificationService.js';
import codeAnalysisService from './services/codeAnalysisService.js';
import { agentWebSocketService } from './services/agentWebSocketService.js';
import { planningWebSocketService } from './services/planningWebSocketService.js';
import { sourceConversationWebSocketService } from './services/sourceConversationWebSocketService.js';
import { connectRedis, disconnectRedis } from './config/redis.js';

// Load environment variables
dotenv.config();

// Initialize Redis
connectRedis().catch(err => {
    console.error('Redis initialization failed:', err);
    console.log('⚠️  Continuing without Redis caching');
});

// Initialize services
bunnyService.initialize();
codeVerificationService.initialize();
codeAnalysisService.initialize();
// Graceful shutdown
process.on('SIGTERM', async () => {
    console.log('SIGTERM received, shutting down gracefully...');
    await disconnectRedis();
    process.exit(0);
});

process.on('SIGINT', async () => {
    console.log('SIGINT received, shutting down gracefully...');
    await disconnectRedis();
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
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'X-User-Api-Key'],
    credentials: true,
}));

// Handle preflight requests explicitly
app.options('*', cors());

app.use(express.json({ limit: '100mb' }));
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

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/notebooks', notebooksRoutes);
app.use('/api/sources', sourcesRoutes);
app.use('/api/chunks', chunksRoutes);
app.use('/api/tags', tagsRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/subscriptions', subscriptionsRoutes);
app.use('/api/rag', ragRoutes); // Moved up and given specific prefix
app.use('/api/agent-skills', agentSkillsRoutes); // Moved up
app.use('/api/admin', adminRoutes);
app.use('/api/analytics', analyticsRoutes);
app.use('/api/media', mediaRoutes);
app.use('/api/sharing', sharingRoutes);
app.use('/api/recommendations', recommendationsRoutes);
app.use('/api/gamification', gamificationRoutes);
app.use('/api/study', studyRoutes);
app.use('/api/ebooks', ebookRoutes);
app.use('/api/research/deep', deepResearchRoutes); // Specific subpath
app.use('/api/research', researchRoutes);
app.use('/api/search', searchRoutes);
app.use('/api/features', featuresRoutes);
app.use('/api/voice', voiceRoutes);
app.use('/api/sports', sportsRoutes);
app.use('/api/coding-agent', codingAgentRoutes);
app.use('/api/mcp', mcpDownloadRoutes);
app.use('/api/github', githubRoutes);
app.use('/api/planning', planningRoutes);
app.use('/api/social', socialRoutes);
app.use('/api/social-sharing', socialSharingRoutes);
app.use('/api/messaging', messagingRoutes);
app.use('/api/notifications', notificationsRoutes);
app.use('/api/google-drive', googleDriveRoutes);
app.use('/api/content', contentRoutes);
app.use('/', publicPagesRoutes);
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

// Initialize WebSocket service for real-time planning updates
planningWebSocketService.initialize(server);

// Initialize WebSocket service for live source conversation updates
sourceConversationWebSocketService.initialize(server);

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
        console.log(`📋 Planning WebSocket available at ws://localhost:${activePort}/ws/planning`);
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

startListening();

export default app;
