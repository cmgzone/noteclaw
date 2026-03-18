# GitHub File Viewer Troubleshooting Guide

## Issue: Still Can't Open GitHub Files After Rebuild

### Step 1: Check What Error You're Seeing

When you try to open a GitHub file, what happens?

**A) Loading forever (spinner never stops)**
- This suggests a backend or network issue
- Go to Step 2

**B) Shows an error message**
- Note the exact error message
- Go to Step 3

**C) App crashes**
- Check Flutter logs
- Go to Step 4

### Step 2: Backend Connection Issues

If files are loading forever, check:

1. **Is your backend running?**
   ```powershell
   # Check if backend is running on port 3000
   netstat -ano | findstr :3000
   ```

2. **Check backend logs**
   - Look for errors in your backend console
   - Check for GitHub API errors

3. **Test the endpoint directly**
   ```powershell
   # Replace with your actual values
   curl http://localhost:3000/api/github/repos/OWNER/REPO/contents/PATH `
     -H "Authorization: Bearer YOUR_TOKEN"
   ```

4. **Check .env file**
   - Verify `BACKEND_URL` is correct in your Flutter `.env`
   - Should be `http://localhost:3000` for local development

### Step 3: Specific Error Messages

**"GitHub not connected"**
- Go to Settings → GitHub
- Reconnect your GitHub account
- Make sure you granted the right permissions

**"Repository access denied"**
- The repository might be private
- Check your GitHub token has access to the repo
- Try with a public repository first

**"File not found"**
- The file path might be incorrect
- Check if the file exists in the repository
- Try a different file

**"Request timed out"**
- Your internet connection might be slow
- The GitHub API might be slow
- Try again in a few moments

**"Rate limit exceeded"**
- You've made too many GitHub API requests
- Wait an hour for the limit to reset
- Or use a GitHub token with higher limits

### Step 4: Check Flutter Logs

Run your app with logging enabled:

```powershell
flutter run --verbose
```

Look for these log messages:
- `[API] GET /github/repos/...` - Shows the API call
- `[API] GET ... - status: XXX` - Shows the response status
- `Error fetching file content:` - Shows the actual error

### Step 5: Verify GitHub Connection

1. Open your app
2. Go to Settings
3. Find GitHub section
4. Check if it shows "Connected"
5. If not, click "Connect GitHub"
6. Follow the OAuth flow

### Step 6: Test with a Simple File

Try opening a small, simple file first:

1. Go to a public repository (like `flutter/flutter`)
2. Navigate to `README.md`
3. Try to open it
4. If this works, the issue is with specific files

### Step 7: Check Backend GitHub Route

The backend might have an issue. Check:

```typescript
// backend/src/routes/github.ts
// Line ~530: GET /api/github/repos/:owner/:repo/contents/*
```

Make sure:
- The route is registered
- GitHub service is initialized
- Database connection is working

### Step 8: Clear App Cache

Sometimes cached data causes issues:

**On Android:**
1. Settings → Apps → NoteClaw
2. Storage → Clear Cache
3. Restart app

**On iOS:**
1. Delete and reinstall the app

**On Desktop:**
1. Delete the app data folder
2. Rebuild and run

### Step 9: Check Network Requests

Use a network inspector to see what's happening:

1. **Flutter DevTools**
   ```powershell
   flutter pub global activate devtools
   flutter pub global run devtools
   ```

2. **Check Network Tab**
   - See if requests are being made
   - Check response status codes
   - Look at response bodies

### Step 10: Minimal Test Case

Create a test to isolate the issue:

```dart
// Test the GitHub service directly
final service = GitHubService(apiService);
try {
  final file = await service.getFileContent(
    'flutter',
    'flutter',
    'README.md',
  );
  print('Success: ${file.name}');
} catch (e) {
  print('Error: $e');
}
```

## Common Solutions

### Solution 1: Backend Not Running
```powershell
cd backend
npm run dev
```

### Solution 2: Wrong Backend URL
Check `.env` file:
```
BACKEND_URL=http://localhost:3000
```

### Solution 3: GitHub Token Expired
1. Go to GitHub Settings → Developer Settings → Personal Access Tokens
2. Generate a new token
3. Reconnect in the app

### Solution 4: CORS Issues
If running on web, check backend CORS settings:
```typescript
// backend/src/index.ts
app.use(cors({
  origin: ['http://localhost:3000', 'http://localhost:8080'],
  credentials: true
}));
```

### Solution 5: Path Encoding Issues
Some file paths with special characters might fail. Try:
- Files without spaces
- Files in root directory
- Files with simple names

## Still Not Working?

If none of these steps work, please provide:

1. **Exact error message** (screenshot if possible)
2. **Flutter logs** (run with `flutter run --verbose`)
3. **Backend logs** (from your backend console)
4. **Network request details** (from DevTools)
5. **Which file you're trying to open** (owner/repo/path)

This will help diagnose the specific issue you're facing.

## Quick Diagnostic Commands

Run these to gather information:

```powershell
# Check Flutter version
flutter --version

# Check if backend is running
netstat -ano | findstr :3000

# Test backend health
curl http://localhost:3000/health

# Check Flutter logs
flutter logs

# Rebuild with verbose output
flutter clean
flutter pub get
flutter run --verbose
```
