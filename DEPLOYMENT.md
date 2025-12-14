# Deploy Your Music Server to the Cloud

## ⭐ Recommended: Railway (Simplest)

### Step 1: Install Railway CLI
```bash
npm install -g @railway/cli
```

### Step 2: Login
```bash
railway login
```

### Step 3: Deploy
```bash
cd /Users/deven/Documents/Ajitesh/Audio/server
railway init
railway up
```

### Step 4: Get Your URL
```bash
railway domain
```
This will give you a URL like: `https://your-app-name.up.railway.app`

### Step 5: Update iOS App
1. Open the app
2. Go to Profile
3. Tap "Server URL"
4. Enter: `your-app-name.up.railway.app` (without https://)
5. Save

### Done! 🎉
Your server is now live and accessible from anywhere!

---

## Alternative: Render.com (Free Tier with Auto-Sleep)

1. **Push to GitHub**
   ```bash
   cd /Users/deven/Documents/Ajitesh/Audio/server
   git init
   git add .
   git commit -m "Initial server code"
   git remote add origin YOUR_GITHUB_URL
   git push -u origin main
   ```

2. **Deploy on Render**
   - Go to https://render.com
   - New → Web Service
   - Connect GitHub repo
   - Root Directory: `server`
   - Build Command: `npm install`
   - Start Command: `node server.js`
   - Instance Type: Free

3. **Note**: Free tier spins down after 15 mins of inactivity. First request will be slow.

---

## Alternative: Fly.io (Free Tier)

```bash
# Install flyctl
brew install flyctl

# Login
fly auth login

# Deploy
cd /Users/deven/Documents/Ajitesh/Audio/server
fly launch
fly deploy
```

---

## Cost Comparison

| Platform | Free Tier | Always On | Cold Start | Best For |
|----------|-----------|-----------|------------|----------|
| Railway | $5 credit/mo (~500hrs) | ✅ Yes | None | Best overall |
| Render | Unlimited with limits | ❌ No | 30-60s | Budget |
| Fly.io | 3 VMs, 256MB | ✅ Yes | None | Tech-savvy |

---

## After Deployment

Your server URL will be something like:
- Railway: `your-app.up.railway.app`
- Render: `your-app.onrender.com`  
- Fly.io: `your-app.fly.dev`

**Update in iOS app**: Profile → Server URL → Enter just the domain (no http:// or :3001)

---

## Troubleshooting

### Server not responding
1. Check Railway logs: `railway logs`
2. Make sure PORT environment variable is set
3. Verify CORS is enabled for all origins

### Downloads failing
- RapidAPI key might have expired
- Check your RapidAPI account quota

### Whisper slow
- Railway/Render free tiers have limited CPU
- Consider upgrading or using Fly.io which has better CPU allocation

---

## Keeping It Running

**Railway**: Will run 24/7 until you exhaust the $5 credit (about 2 weeks of continuous use)

**Render Free**: Spins down after 15 minutes idle. First request each time takes 30-60 seconds to wake up.

**Fly.io**: Stays running 24/7 within free tier limits.

**Recommendation**: Start with Railway, it's the easiest and most reliable for private use.

