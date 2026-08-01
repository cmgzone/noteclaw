import express, { type Request, type Response } from 'express';
import { sendPlayTestingInviteEmail } from '../services/emailService.js';
import {
    getPlayTestingSettings,
    joinPlayTestingProgram,
    markPlayTesterInviteSent,
} from '../services/playTesterService.js';

const router = express.Router();
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

router.get('/config', async (_req: Request, res: Response) => {
    try {
        const settings = await getPlayTestingSettings();
        res.json({
            success: true,
            optInUrl: settings.optInUrl,
            groupUrl: settings.groupUrl,
        });
    } catch (error) {
        console.error('Play testing config error:', error);
        res.status(500).json({ error: 'Failed to load the Play testing program' });
    }
});

router.post('/join', async (req: Request, res: Response) => {
    try {
        const email = typeof req.body?.email === 'string'
            ? req.body.email.trim().toLowerCase()
            : '';
        const displayName = typeof req.body?.displayName === 'string'
            ? req.body.displayName.trim()
            : '';
        const consent = req.body?.consent === true;
        const website = typeof req.body?.website === 'string' ? req.body.website.trim() : '';

        if (website) {
            return res.json({ success: true, emailSent: true });
        }
        if (!email || email.length > 254 || !EMAIL_PATTERN.test(email)) {
            return res.status(400).json({ error: 'Enter a valid Google Account email address' });
        }
        if (displayName.length > 80) {
            return res.status(400).json({ error: 'Name must be 80 characters or fewer' });
        }
        if (!consent) {
            return res.status(400).json({ error: 'You must agree to receive the testing invite email' });
        }

        const [{ tester, shouldSendInvite }, settings] = await Promise.all([
            joinPlayTestingProgram({ email, displayName }),
            getPlayTestingSettings(),
        ]);

        let emailSent = tester.inviteEmailSent;
        if (shouldSendInvite) {
            emailSent = await sendPlayTestingInviteEmail({
                to: tester.email,
                displayName: tester.displayName,
                optInUrl: settings.optInUrl,
                groupUrl: settings.groupUrl,
                feedbackEmail: settings.feedbackEmail,
            });
            await markPlayTesterInviteSent(tester.id, emailSent);
        }

        res.status(shouldSendInvite ? 201 : 200).json({
            success: true,
            emailSent,
            optInUrl: settings.optInUrl,
            groupUrl: settings.groupUrl,
            message: emailSent
                ? 'Your Google Play testing invite has been emailed.'
                : 'Your tester request was saved, but the invite email could not be delivered yet.',
        });
    } catch (error) {
        console.error('Join Play testing error:', error);
        res.status(500).json({ error: 'Failed to join the Android testing program' });
    }
});

export default router;
