import express from 'express';
import cors from 'cors';
import YoutubeSearchApi from 'youtube-search-api';
import { fileURLToPath } from 'url';
import { dirname, join, extname, basename } from 'path';
import fs from 'fs';
import os from 'os';
import axios from 'axios';
import dotenv from 'dotenv';
import { exec, spawn } from 'child_process';
import { createWriteStream, promises as fsp } from 'fs';
import crypto from 'crypto';
import {
  detectFirstVocal,
  computeOffset,
  shiftLrc,
  parseFirstLrcTime,
  alignLyricsToWhisper,
  describeAudio
} from './utils/lyrics.js';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3001;

// CORS configuration - allow all origins for private use
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST'],
  credentials: true
}));

// RapidAPI configuration
const RAPIDAPI_KEY = process.env.RAPIDAPI_KEY || '5a2bd678camsh6ae73794f0bd56fp1c7f49jsn1e92cc36ecd3';
const RAPIDAPI_HOST = 'youtube-mp36.p.rapidapi.com';

// Cache for audio URLs (expires after 2 hours)
const urlCache = new Map();
const CACHE_DURATION = 2 * 60 * 60 * 1000; // 2 hours in milliseconds

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Create downloads directory if it doesn't exist
const downloadsDir = join(__dirname, 'downloads');
if (!fs.existsSync(downloadsDir)) {
  fs.mkdirSync(downloadsDir);
}
const alignmentsDir = join(__dirname, 'alignments');
if (!fs.existsSync(alignmentsDir)) {
  fs.mkdirSync(alignmentsDir);
}

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', message: 'Server is running' });
});

// ---------- Whisper + Lyrics endpoints ----------
const downloadToTemp = async (audioUrl) => {
  const hash = crypto.createHash('md5').update(audioUrl).digest('hex').slice(0, 8);
  const tempPath = join(os.tmpdir(), `whisper-${hash}.audio`);
  const writer = createWriteStream(tempPath);
  const response = await axios.get(audioUrl, { responseType: 'stream', timeout: 30000 });
  await new Promise((resolve, reject) => {
    response.data.pipe(writer);
    writer.on('finish', resolve);
    writer.on('error', reject);
  });
  return tempPath;
};

const saveBase64AudioToTemp = async (audioBase64, filename = '') => {
  // Support both raw base64 and data URLs (data:audio/mp3;base64,XXXX)
  const base64Payload = audioBase64.includes(',')
    ? audioBase64.split(',').pop()
    : audioBase64;

  const buffer = Buffer.from(base64Payload || '', 'base64');
  if (!buffer.length) {
    throw new Error('Uploaded audio payload was empty or invalid');
  }

  const ext = extname(filename || '') || '.audio';
  const tempPath = join(os.tmpdir(), `whisper-upload-${crypto.randomUUID()}${ext}`);
  await fsp.writeFile(tempPath, buffer);
  return tempPath;
};

const runWhisper = async ({ audioPath, model = process.env.WHISPER_MODEL || 'small', includeTokens = true, language = 'en', task = 'transcribe' }) => {
  // Requires WHISPER_CMD environment variable with placeholders:
  // e.g., WHISPER_CMD="whisper {audio} --model {model} --output_format json --output_dir {output_dir}"
  const template = process.env.WHISPER_CMD;
  if (!template) {
    throw new Error('WHISPER_CMD env var not set. Configure it to point to your Whisper binary with {audio},{model},{output_dir} placeholders.');
  }
  
  const outputDir = join(os.tmpdir(), `whisper-${crypto.randomUUID()}`);
  await fsp.mkdir(outputDir, { recursive: true });
  
  // Get the base name of the audio file (without path, with extension)
  const audioBaseName = basename(audioPath);
  const audioNameWithoutExt = audioBaseName.replace(/\.[^.]+$/, '');
  const expectedOutputFile = join(outputDir, `${audioNameWithoutExt}.json`);
  
  const cmd = template
    .replace('{audio}', `"${audioPath}"`)
    .replace('{model}', process.env.WHISPER_MODEL || model)
    .replace('{output_dir}', `"${outputDir}"`)
    .replace('{tokens}', includeTokens ? 'true' : 'false')
    .replace('{language}', language)
    .replace('{task}', task);

  console.log(`🎙️ Running Whisper: ${cmd}`);
  
  await new Promise((resolve, reject) => {
    exec(cmd, { timeout: 180000, maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        console.error('Whisper stderr:', stderr);
        return reject(new Error(`Whisper failed: ${stderr || error.message}`));
      }
      console.log('✅ Whisper completed');
      resolve(stdout);
    });
  });
  
  // Read the output file
  const content = await fsp.readFile(expectedOutputFile, 'utf8');
  const json = JSON.parse(content);
  
  // Clean up
  await fsp.rm(outputDir, { recursive: true, force: true });
  
  return json;
};

app.post('/api/whisper/segments', async (req, res) => {
  const { audioUrl, model = 'small', includeTokens = true, mockSegments } = req.body || {};
  if (!audioUrl && !mockSegments) {
    return res.status(400).json({ error: 'audioUrl is required (or mockSegments for testing)' });
  }

  try {
    // Allow mockSegments for testing without Whisper binary
    if (mockSegments) {
      const firstVocal = detectFirstVocal(mockSegments);
      return res.json({ firstVocal, segments: mockSegments, tokens: [] });
    }

    const tempPath = await downloadToTemp(audioUrl);
    const whisperJson = await runWhisper({ audioPath: tempPath, model, includeTokens, language: 'en', task: 'transcribe' });

    const segments = whisperJson?.segments || [];
    const tokens = whisperJson?.tokens || [];
    const firstVocal = detectFirstVocal(segments);

    await fsp.rm(tempPath, { force: true });

    return res.json({ firstVocal, segments, tokens });
  } catch (error) {
    console.error('❌ Whisper error:', error.message);
    return res.status(500).json({
      error: 'Failed to run Whisper',
      details: error.message,
      hint: 'Ensure WHISPER_CMD/WHISPER_MODEL_PATH are configured and the binary is installed.'
    });
  }
});

app.post('/api/lyrics/correct', async (req, res) => {
  const { lrc, firstLrcTime, firstVocal, offsetOverride, maxAllowed = 8, precision = 2 } = req.body || {};
  if (!lrc) return res.status(400).json({ error: 'lrc is required' });

  const derivedFirstLrc = firstLrcTime ?? parseFirstLrcTime(lrc);
  const offset = offsetOverride ?? computeOffset(firstVocal, derivedFirstLrc);

  if (offset === null || offset === undefined) {
    return res.status(400).json({ error: 'offset could not be computed', derivedFirstLrc, firstVocal });
  }

  if (Math.abs(offset) > maxAllowed) {
    return res.status(400).json({ error: 'offset too large, confirmation required', offset });
  }

  const correctedLrc = shiftLrc(lrc, offset, { precision, floor: 0 });
  return res.json({ offset, correctedLrc });
});

app.post('/api/lyrics/align', async (req, res) => {
  const { plainLyrics, whisperSegments, whisperTokens } = req.body || {};
  if (!plainLyrics || !Array.isArray(plainLyrics) || !plainLyrics.length) {
    return res.status(400).json({ error: 'plainLyrics array is required' });
  }
  if (!whisperSegments || !Array.isArray(whisperSegments) || !whisperSegments.length) {
    return res.status(400).json({ error: 'whisperSegments are required' });
  }

  const result = alignLyricsToWhisper(plainLyrics, whisperSegments, whisperTokens);
  return res.json(result);
});

// Search YouTube
app.get('/api/search', async (req, res) => {
  try {
    const { q } = req.query;
    
    if (!q) {
      return res.status(400).json({ error: 'Search query is required' });
    }
    
    console.log(`🔍 Searching YouTube for: "${q}"`);
    
    // Add timeout to prevent hanging
    const searchPromise = YoutubeSearchApi.GetListByKeyword(q, false, 10);
    const timeoutPromise = new Promise((_, reject) => 
      setTimeout(() => reject(new Error('Search timeout')), 10000)
    );
    
    const results = await Promise.race([searchPromise, timeoutPromise]);
    
    console.log(`✅ Found ${results.items?.length || 0} results`);
    
    const videos = results.items.map(item => ({
      id: item.id,
      title: item.title,
      thumbnail: item.thumbnail.thumbnails[0].url,
      channel: item.channelTitle,
      duration: item.length?.simpleText || 'Unknown'
    }));
    
    res.json(videos);
  } catch (error) {
    console.error('Error searching YouTube:', error.message);
    res.status(500).json({ error: 'Failed to search YouTube: ' + error.message });
  }
});

// Get video info using RapidAPI
app.get('/api/video-info/:videoId', async (req, res) => {
  try {
    const { videoId } = req.params;
    
    console.log(`📹 Getting info for: ${videoId}`);
    
    const response = await axios.get(`https://${RAPIDAPI_HOST}/dl`, {
      params: { id: videoId },
      headers: {
        'X-RapidAPI-Key': RAPIDAPI_KEY,
        'X-RapidAPI-Host': RAPIDAPI_HOST
      },
      timeout: 15000
    });
    
    res.json({
      title: response.data.title,
      author: response.data.author || 'Unknown',
      duration: response.data.duration || 0,
      thumbnail: `https://img.youtube.com/vi/${videoId}/maxresdefault.jpg`
    });
  } catch (error) {
    console.error('❌ Error getting video info:', error.message);
    res.status(500).json({ error: 'Failed to get video info', details: error.message });
  }
});

// Align lyrics using local whisper/whisperx script
app.post('/api/align', express.json(), async (req, res) => {
  try {
    const { audioPath, lyrics } = req.body;
    if (!audioPath || !lyrics) return res.status(400).json({ error: 'audioPath and lyrics required' });

    const { spawn } = await import('child_process');
    const py = spawn('python3', [join(__dirname, 'align_whisper.py'), audioPath, lyrics]);
    let out = '';
    let err = '';
    py.stdout.on('data', c => out += c.toString());
    py.stderr.on('data', c => err += c.toString());
    py.on('close', code => {
      if (code !== 0) {
        console.error('align script error', err);
        return res.status(500).json({ error: 'align failed', reason: err });
      }
      try {
        const parsed = JSON.parse(out);
        return res.json(parsed);
      } catch (e) {
        return res.status(500).json({ error: 'invalid align output', raw: out });
      }
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});


// Stream audio using RapidAPI
app.get('/api/download/:videoId', async (req, res) => {
  try {
    const { videoId } = req.params;
    
    console.log(`📥 Streaming audio via RapidAPI for: ${videoId}`);

    // Get audio URL from RapidAPI
    const response = await axios.get(`https://${RAPIDAPI_HOST}/dl`, {
      params: { id: videoId },
      headers: {
        'X-RapidAPI-Key': RAPIDAPI_KEY,
        'X-RapidAPI-Host': RAPIDAPI_HOST
      },
      timeout: 15000
    });

    const audioUrl = response.data.link;
    if (!audioUrl) {
      throw new Error('No audio URL in response');
    }

    console.log(`✅ Got audio URL, proxying stream...`);

    // Stream the audio from RapidAPI URL
    const audioResponse = await axios({
      method: 'get',
      url: audioUrl,
      responseType: 'stream',
      timeout: 0
    });

    res.setHeader('Content-Type', 'audio/mpeg');
    res.setHeader('Content-Disposition', `attachment; filename="${videoId}.mp3"`);

    audioResponse.data.pipe(res);

    audioResponse.data.on('error', (error) => {
      console.error('❌ Audio stream error:', error.message);
      if (!res.headersSent) {
        res.status(500).json({ error: 'Failed to stream audio' });
      }
    });

    audioResponse.data.on('end', () => {
      console.log(`✅ Finished streaming: ${videoId}`);
    });
    
  } catch (error) {
    console.error('❌ Error downloading audio:', error.message);
    res.status(500).json({ error: 'Failed to download audio', details: error.message });
  }
});

// Get direct audio URL using RapidAPI
app.get('/api/audio-url/:videoId', async (req, res) => {
  try {
    const { videoId } = req.params;
    
    // Check cache first
    const cached = urlCache.get(videoId);
    if (cached && (Date.now() - cached.timestamp < CACHE_DURATION)) {
      console.log(`⚡ Using cached URL for: ${videoId}`);
      return res.json({ url: cached.url, cached: true });
    }
    
    console.log(`🎵 Getting audio URL for: ${videoId}`);
    const startTime = Date.now();
    
    const response = await axios.get(`https://${RAPIDAPI_HOST}/dl`, {
      params: { id: videoId },
      headers: {
        'X-RapidAPI-Key': RAPIDAPI_KEY,
        'X-RapidAPI-Host': RAPIDAPI_HOST
      },
      timeout: 15000
    });
    
    const audioUrl = response.data.link;
    
    if (!audioUrl) {
      throw new Error('No audio URL in response');
    }
    
    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`✅ Got audio URL in ${duration}s`);
    
    // Cache the URL
    urlCache.set(videoId, {
      url: audioUrl,
      timestamp: Date.now()
    });
    
    res.json({ 
      url: audioUrl, 
      cached: false,
      title: response.data.title
    });
    
  } catch (error) {
    console.error('❌ Error getting audio URL:', error.message);
    console.error('Response:', error.response?.data);
    res.status(error.response?.status || 500).json({ 
      error: error.response?.data?.message || 'Failed to get audio URL', 
      details: error.message
    });
  }
});

// Download audio to server and trigger one-time alignment in background
app.post('/api/download-sync/:videoId', async (req, res) => {
  try {
    const { videoId } = req.params;
    console.log(`\n========================================`);
    console.log(`📥 DOWNLOAD-SYNC REQUEST`);
    console.log(`Video ID: ${videoId}`);
    console.log(`Title: ${req.body?.title || 'NOT PROVIDED'}`);
    console.log(`Artist: ${req.body?.artist || 'NOT PROVIDED'}`);
    console.log(`Full body:`, JSON.stringify(req.body));
    console.log(`========================================\n`);
    
    const alignmentPath = join(alignmentsDir, `${videoId}.json`);

    // If alignment already exists, check if it's valid
    if (fs.existsSync(alignmentPath)) {
      const data = fs.readFileSync(alignmentPath, 'utf8');
      const parsed = JSON.parse(data);
      
      // Check if it's an error file or empty
      if (parsed.error || (Array.isArray(parsed) && parsed.length === 0) || 
          (Array.isArray(parsed) && parsed.length === 1 && !parsed[0].line)) {
        console.log(`⚠️  Found invalid alignment, deleting and reprocessing...`);
        fs.unlinkSync(alignmentPath);
      } else {
        console.log(`✅ Returning existing alignment (${parsed.length} lines)`);
        return res.json({ status: 'ready', alignment: parsed });
      }
    }

    // Look for any existing audio file (m4a, webm, mp3, etc.)
    const possibleFormats = ['.m4a', '.webm', '.mp3', '.mp4', '.wav'];
    let audioPath = null;
    for (const ext of possibleFormats) {
      const testPath = join(downloadsDir, `${videoId}${ext}`);
      if (fs.existsSync(testPath)) {
        const stats = fs.statSync(testPath);
        if (stats.size > 0) {
          audioPath = testPath;
          console.log(`✅ Found existing audio file: ${audioPath}`);
          break;
        }
      }
    }

    // If no valid audio file, download using yt-dlp (primary) or RapidAPI (fallback)
    if (!audioPath) {
      const outPath = join(downloadsDir, `${videoId}.mp3`);
      
      // Try yt-dlp first (works from any server)
      try {
        console.log(`⬇️  Attempting yt-dlp download...`);
        console.log(`🎵 Downloading YouTube audio: ${videoId}`);
        
        const { execSync } = require('child_process');
        
        // Download using yt-dlp with best audio quality
        const ytdlpCommand = `yt-dlp -x --audio-format mp3 --audio-quality 0 -o "${outPath}" "https://www.youtube.com/watch?v=${videoId}"`;
        console.log(`📍 Running: ${ytdlpCommand}`);
        
        execSync(ytdlpCommand, { 
          stdio: 'inherit',
          timeout: 60000 // 60 second timeout
        });

        console.log(`✅ yt-dlp Download complete: ${outPath}`);
        audioPath = outPath;
      } catch (ytdlpError) {
        console.warn(`⚠️  yt-dlp failed, trying RapidAPI fallback...`);
        console.warn(`   Error: ${ytdlpError.message}`);
        
        // Fallback to RapidAPI
        try {
          console.log(`🔑 Using RapidAPI: ${RAPIDAPI_HOST}`);
          console.log(`📍 Request URL: https://${RAPIDAPI_HOST}/dl?id=${videoId}`);
          
          const response = await axios.get(`https://${RAPIDAPI_HOST}/dl`, {
            params: { id: videoId },
            headers: {
              'X-RapidAPI-Key': RAPIDAPI_KEY,
              'X-RapidAPI-Host': RAPIDAPI_HOST
            },
            timeout: 15000
          });
          
          console.log(`✅ RapidAPI response status: ${response.status}`);
          const audioUrl = response.data.link;
          
          if (!audioUrl) {
            throw new Error('No audio URL in RapidAPI response');
          }

          console.log(`📥 Downloading audio from RapidAPI URL...`);
          
          // Download the audio file
          const audioResponse = await axios({
            method: 'get',
            url: audioUrl,
            responseType: 'stream'
          });

          const writer = fs.createWriteStream(outPath);
          audioResponse.data.pipe(writer);

          await new Promise((resolve, reject) => {
            writer.on('finish', resolve);
            writer.on('error', reject);
          });

          console.log(`✅ RapidAPI Download complete: ${outPath}`);
          audioPath = outPath;
        } catch (rapidapiError) {
          console.error(`❌ Both yt-dlp and RapidAPI failed`);
          console.error(`   yt-dlp: ${ytdlpError.message}`);
          console.error(`   RapidAPI: ${rapidapiError.message}`);
          return res.status(500).json({ 
            error: 'Download failed', 
            message: `Both methods failed - yt-dlp: ${ytdlpError.message}, RapidAPI: ${rapidapiError.message}`,
            ytdlpError: ytdlpError.message,
            rapidapiError: rapidapiError.message
          });
        }
      }
    }

    // Spawn background alignment if not already running/exists
    const lockPath = alignmentPath + '.lock';
    
    // Check for stale lock files (older than 5 minutes)
    if (fs.existsSync(lockPath)) {
      try {
        const lockData = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
        const age = Date.now() - lockData.started;
        if (age > 5 * 60 * 1000) {
          console.log(`⚠️  Removing stale lock (${Math.floor(age/1000)}s old)`);
          fs.unlinkSync(lockPath);
        }
      } catch (e) {
        console.log(`⚠️  Invalid lock file, removing`);
        fs.unlinkSync(lockPath);
      }
    }
    
    if (!fs.existsSync(alignmentPath) && !fs.existsSync(lockPath)) {
      // Fetch lyrics from LRCLIB if metadata provided
      let lyricsText = '';
      const { title, artist } = req.body || {};
      if (title) {
        try {
          console.log(`🔍 Fetching lyrics for: ${artist || 'Unknown'} - ${title}`);
          const lrclibUrl = `https://lrclib.net/api/get?artist_name=${encodeURIComponent(artist || '')}&track_name=${encodeURIComponent(title)}`;
          const lrcResponse = await axios.get(lrclibUrl, { timeout: 15000 });
          if (lrcResponse.data && lrcResponse.data.plainLyrics) {
            const lines = lrcResponse.data.plainLyrics.split('\n').filter(l => l.trim());
            // If LRCLIB has fewer than 60 lines, it's probably incomplete - use Whisper instead
            if (lines.length < 60) {
              console.log(`⚠️  LRCLIB lyrics too sparse (${lines.length} lines), using Whisper transcription for complete coverage`);
              lyricsText = '';
            } else {
              lyricsText = lrcResponse.data.plainLyrics;
              console.log(`✅ Found LRCLIB lyrics (${lines.length} lines)`);
            }
          } else {
            console.log(`⚠️  LRCLIB returned no lyrics, will use Whisper transcription`);
          }
        } catch (e) {
          console.log(`⚠️  LRCLIB failed (${e.message}), will use Whisper transcription`);
        }
      }
      
      // create lock file to mark job in progress
      fs.writeFileSync(lockPath, JSON.stringify({ pid: process.pid, started: Date.now() }));
      console.log(`🎯 Starting background alignment for ${videoId} with ${lyricsText.split('\n').length} lyric lines`);
      
      try {
        const { spawn } = await import('child_process');
        const pythonPath = join(__dirname, '.venv', 'bin', 'python3');
        const py = spawn(pythonPath, [join(__dirname, 'align_whisper.py'), audioPath, lyricsText]);

        let out = '';
        let err = '';
        py.stdout.on('data', c => out += c.toString());
        py.stderr.on('data', c => {
          const msg = c.toString();
          err += msg;
          // Log warnings but don't treat them as errors
          if (msg.includes('UserWarning') || msg.includes('FP16 is not supported')) {
            console.log(`⚠️  Whisper warning: ${msg.trim()}`);
          }
        });
        
        py.on('error', (error) => {
          console.log(`⚠️  Python alignment skipped (${error.message})`);
          // Write empty alignment instead of crashing
          fs.writeFileSync(alignmentPath, JSON.stringify({ error: true, reason: 'Python environment not available', skipped: true }));
          try { fs.unlinkSync(lockPath); } catch (e) { /* ignore */ }
        });
        
        py.on('close', code => {
          try {
            if (code !== 0) {
              console.error(`❌ Alignment failed for ${videoId} (exit code ${code}):`, err);
              fs.writeFileSync(alignmentPath, JSON.stringify({ error: true, reason: err }));
              return;
            }
            // Try to parse output even if there were warnings
            try {
              const parsed = JSON.parse(out);
              fs.writeFileSync(alignmentPath, JSON.stringify(parsed));
              console.log(`✅ Alignment saved: ${alignmentPath} (${parsed.length} lines)`);
            } catch (parseError) {
              console.error(`❌ Failed to parse alignment output for ${videoId}:`, parseError.message);
              console.log('Raw output:', out);
              fs.writeFileSync(alignmentPath, JSON.stringify({ error: true, raw: out, parseError: String(parseError) }));
            }
          } catch (e) {
            console.error('invalid align output', e, out);
            fs.writeFileSync(alignmentPath, JSON.stringify({ error: true, raw: out, parseError: String(e) }));
          } finally {
            // remove lock
            try { fs.unlinkSync(lockPath); } catch (e) { /* ignore */ }
          }
        });
      } catch (spawnError) {
        console.log(`⚠️  Python alignment skipped (${spawnError.message})`);
        // Write empty alignment and clean up lock
        fs.writeFileSync(alignmentPath, JSON.stringify({ error: true, reason: 'Python environment not available', skipped: true }));
        try { fs.unlinkSync(lockPath); } catch (e) { /* ignore */ }
      }
    }

    res.json({ status: 'started', path: audioPath });
  } catch (e) {
    console.error('download-sync error', e);
    res.status(500).json({ error: e.message });
  }
});

// Retrieve saved alignment for a video
app.get('/api/lyrics/:videoId', async (req, res) => {
  try {
    const { videoId } = req.params;
    const alignmentPath = join(alignmentsDir, `${videoId}.json`);
    const lockPath = alignmentPath + '.lock';

    if (fs.existsSync(alignmentPath)) {
      const data = fs.readFileSync(alignmentPath, 'utf8');
      return res.json({ status: 'ready', alignment: JSON.parse(data) });
    }

    if (fs.existsSync(lockPath)) {
      // job is in progress
      return res.json({ status: 'in-progress' });
    }

    // Return 200 with not-found status (not 404, so app doesn't see it as error)
    return res.json({ status: 'not-found' });
  } catch (e) {
    console.error('lyrics fetch error', e);
    res.status(500).json({ error: e.message });
  }
});

// Get alignment queue status for developer dashboard
app.get('/api/alignment-status', async (req, res) => {
  try {
    const files = fs.readdirSync(alignmentsDir);
    const lockFiles = files.filter(f => f.endsWith('.lock'));
    const completedFiles = files.filter(f => f.endsWith('.json') && !f.endsWith('.lock'));
    
    // Get in-progress items
    const inProgress = lockFiles.map(lockFile => {
      const videoId = lockFile.replace('.json.lock', '');
      const lockPath = join(alignmentsDir, lockFile);
      try {
        const lockData = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
        return {
          videoId,
          started: lockData.started,
          pid: lockData.pid,
        };
      } catch (e) {
        return {
          videoId,
          started: Date.now(),
          error: 'Could not read lock file'
        };
      }
    });
    
    // Get recent history (last 20 completed)
    const history = completedFiles
      .map(file => {
        const videoId = file.replace('.json', '');
        const alignmentPath = join(alignmentsDir, file);
        try {
          const stats = fs.statSync(alignmentPath);
          const data = JSON.parse(fs.readFileSync(alignmentPath, 'utf8'));
          return {
            videoId,
            completed: stats.mtime.getTime(),
            error: data.error ? data.reason : null,
            duration: null, // Could track this if we store start time
          };
        } catch (e) {
          return null;
        }
      })
      .filter(Boolean)
      .sort((a, b) => b.completed - a.completed)
      .slice(0, 20);
    
    res.json({
      inProgress,
      completed: completedFiles.length,
      history,
    });
  } catch (e) {
    console.error('alignment-status error', e);
    res.status(500).json({ error: e.message });
  }
});

// Get audio stream URL (for playing without downloading)
app.get('/api/stream/:videoId', async (req, res) => {
  try {
    const { videoId } = req.params;
    const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;
    
    res.setHeader('Content-Type', 'audio/mpeg');
    res.setHeader('Accept-Ranges', 'bytes');
    
    // Stream audio directly using yt-dlp
    const ytdlp = exec(`yt-dlp -f "bestaudio" -o - "${videoUrl}"`);
    ytdlp.stdout.pipe(res);
    
    ytdlp.on('error', (error) => {
      console.error('Error streaming:', error);
      if (!res.headersSent) {
        res.status(500).json({ error: 'Failed to stream audio' });
      }
    });
    
  } catch (error) {
    console.error('Error streaming audio:', error);
    res.status(500).json({ error: 'Failed to stream audio' });
  }
});

// Fetch captions (YouTube) as raw XML (srt-like) so client can parse to LRC
app.get('/api/captions/:videoId', async (req, res) => {
  const { videoId } = req.params;
  try {
    console.log(`📝 Fetching captions for ${videoId}`);
    const info = await ytdl.getInfo(videoId);
    const tracks = info?.player_response?.captions?.playerCaptionsTracklistRenderer?.captionTracks || [];
    if (!tracks.length) {
      return res.status(404).json({ error: 'No captions available' });
    }

    const preferredTrack =
      tracks.find(t => (t.languageCode || '').startsWith('en')) ||
      tracks[0];

    let captionUrl = preferredTrack.baseUrl;
    if (!captionUrl) {
      return res.status(404).json({ error: 'Caption URL missing' });
    }

    // Ensure XML payload
    if (!captionUrl.includes('&fmt=')) {
      captionUrl += '&fmt=3';
    }

    const captionResponse = await axios.get(captionUrl, { responseType: 'text', timeout: 15000 });
    res.json({
      captions: captionResponse.data,
      language: preferredTrack.languageCode,
      kind: preferredTrack.kind,
    });
  } catch (error) {
    console.error('❌ Captions fetch error:', error.message);
    res.status(500).json({ error: 'Failed to fetch captions', details: error.message });
  }
});

// Download and save audio file, return local URL
app.post('/api/download-audio', async (req, res) => {
  try {
    const { videoId, title, artist } = req.body;
    
    if (!videoId) {
      return res.status(400).json({ error: 'videoId is required' });
    }
    
    const filename = `${videoId}.mp3`;
    const filepath = join(downloadsDir, filename);
    
    // Check if already downloaded
    if (fs.existsSync(filepath)) {
      console.log(`✅ File already exists: ${filename}`);
      const stats = fs.statSync(filepath);
      return res.json({
        success: true,
        audioUrl: `http://192.168.1.133:${PORT}/downloads/${filename}`,
        duration: 180, // We'll get this from player
        title: title || 'Unknown',
        artist: artist || 'Unknown',
        cached: true,
        size: stats.size
      });
    }
    
    console.log(`📥 Downloading audio for: ${videoId} - ${title}`);
    
    // Download using yt-dlp
    const ytdlp = spawn('yt-dlp', [
      '-f', 'bestaudio[ext=m4a]/bestaudio',
      '--extract-audio',
      '--audio-format', 'mp3',
      '--audio-quality', '0',
      '-o', filepath,
      `https://www.youtube.com/watch?v=${videoId}`
    ]);
    
    let errorOutput = '';
    
    ytdlp.stderr.on('data', (data) => {
      const msg = data.toString();
      errorOutput += msg;
      console.log(`yt-dlp: ${msg.trim()}`);
    });
    
    ytdlp.on('close', (code) => {
      if (code === 0 && fs.existsSync(filepath)) {
        const stats = fs.statSync(filepath);
        console.log(`✅ Downloaded: ${filename} (${(stats.size / 1024 / 1024).toFixed(2)} MB)`);
        
        res.json({
          success: true,
          audioUrl: `http://192.168.1.133:${PORT}/downloads/${filename}`,
          duration: 180,
          title: title || 'Unknown',
          artist: artist || 'Unknown',
          cached: false,
          size: stats.size
        });
      } else {
        console.error(`❌ yt-dlp failed with code ${code}`);
        res.status(500).json({ 
          error: 'Download failed', 
          details: errorOutput,
          code 
        });
      }
    });
    
    ytdlp.on('error', (error) => {
      console.error('❌ yt-dlp error:', error);
      res.status(500).json({ error: 'Failed to spawn yt-dlp', details: error.message });
    });
    
  } catch (error) {
    console.error('❌ Download error:', error);
    res.status(500).json({ error: 'Download failed', details: error.message });
  }
});

// Serve downloaded files
app.use('/downloads', express.static(downloadsDir));

// Debug endpoint to check environment variables (for troubleshooting)
app.get('/api/debug/env', (req, res) => {
  res.json({
    hasRapidApiKey: !!process.env.RAPIDAPI_KEY,
    rapidApiKeyLength: process.env.RAPIDAPI_KEY ? process.env.RAPIDAPI_KEY.length : 0,
    rapidApiKeyPrefix: process.env.RAPIDAPI_KEY ? process.env.RAPIDAPI_KEY.substring(0, 10) + '...' : 'NOT SET',
    rapidApiHost: RAPIDAPI_HOST,
    hasSpotifyClientId: !!process.env.SPOTIFY_CLIENT_ID,
    hasSpotifyClientSecret: !!process.env.SPOTIFY_CLIENT_SECRET
  });
});

// ---------- Spotify OAuth Token Exchange ----------
app.post('/api/spotify/token', async (req, res) => {
  try {
    const { code, redirect_uri } = req.body;
    
    if (!code) {
      return res.status(400).json({ error: 'Authorization code is required' });
    }
    
    // Exchange authorization code for access token
    const clientId = process.env.SPOTIFY_CLIENT_ID;
    const clientSecret = process.env.SPOTIFY_CLIENT_SECRET;
    
    if (!clientId || !clientSecret) {
      return res.status(500).json({ error: 'Spotify credentials not configured. Add SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET to .env file' });
    }
    
    const tokenUrl = 'https://accounts.spotify.com/api/token';
    const authHeader = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
    
    const params = new URLSearchParams({
      grant_type: 'authorization_code',
      code: code,
      redirect_uri: redirect_uri
    });
    
    const response = await axios.post(tokenUrl, params.toString(), {
      headers: {
        'Authorization': `Basic ${authHeader}`,
        'Content-Type': 'application/x-www-form-urlencoded'
      }
    });
    
    res.json(response.data);
  } catch (error) {
    console.error('Error exchanging Spotify token:', error.response?.data || error);
    res.status(500).json({ 
      error: 'Failed to exchange token',
      details: error.response?.data || error.message
    });
  }
});

// Whisper transcribe-only endpoint (no lyrics alignment, just transcribe audio)
app.post('/api/whisper/transcribe', async (req, res) => {
  let tempPath;
  try {
    const { audioUrl, audioBase64, filename, language = 'en' } = req.body || {};
    
    if (!audioUrl && !audioBase64) {
      return res.status(400).json({ error: 'audioUrl or audioBase64 is required' });
    }
    
    if (audioBase64) {
      console.log(`🎤 Transcribing uploaded audio (${filename || 'unnamed'})`);
      tempPath = await saveBase64AudioToTemp(audioBase64, filename);
    } else {
      console.log(`🎤 Transcribing audio from URL: ${audioUrl.substring(0, 80)}...`);
      tempPath = await downloadToTemp(audioUrl);
    }
    
    console.log(`📥 Audio ready at temp path: ${tempPath}`);
    console.log(`🎙️ Running Whisper transcription (language: ${language})...`);
    
    const whisperJson = await runWhisper({ 
      audioPath: tempPath, 
      includeTokens: false, 
      language, 
      task: 'transcribe' 
    });
    
    const segments = whisperJson?.segments || [];
    
    if (!segments.length) {
      console.log(`⚠️ Whisper returned no segments`);
      return res.status(500).json({ error: 'No transcription segments returned' });
    }
    
    console.log(`✅ Whisper completed: ${segments.length} segments`);
    
    // Auto-detect offset: use the first segment's start time
    // This represents when Whisper first detected audio content
    let detectedOffset = 0;
    console.log(`🔍 Offset detection: segments=${segments.length}`);
    
    if (segments.length > 0) {
      detectedOffset = segments[0].start;
      console.log(`🎯 Auto-detected offset: ${detectedOffset.toFixed(2)}s (first segment @ ${detectedOffset.toFixed(2)}s)`);
    } else {
      console.log(`⚠️ No segments available, using 0 offset`);
    }
    
    // Convert segments to lyrics lines
    const lines = segments.map(seg => ({
      line: seg.text.trim(),
      start: Math.max(0, seg.start - detectedOffset),
      end: Math.max(0, seg.end - detectedOffset)
    })).filter(line => line.line.length > 0);
    
    return res.json({ lines, offset: detectedOffset });
  } catch (error) {
    console.error('❌ Error in Whisper transcription:', error);
    res.status(500).json({ 
      error: 'Whisper transcription failed', 
      details: error.message 
    });
  } finally {
    if (tempPath) {
      try { await fsp.rm(tempPath, { force: true }); } catch (e) { /* ignore cleanup errors */ }
    }
  }
});

// Whisper alignment for mobile - anchor-based (segments -> deterministic alignment)
app.post('/api/whisper/align-mobile', async (req, res) => {
  let tempPath;
  try {
    const { audioUrl, audioBase64, filename, lyrics } = req.body || {};
    
    if ((!audioUrl && !audioBase64) || !lyrics) {
      return res.status(400).json({ error: 'audioUrl or audioBase64 and lyrics are required' });
    }
    
    const lyricsText = lyrics || '';
    const plainLines = lyricsText.split('\n').map(l => l.trim()).filter(Boolean);
    if (!plainLines.length) {
      return res.status(400).json({ error: 'lyrics are required for alignment' });
    }
    
    if (audioBase64) {
      console.log(`🎵 Aligning lyrics for uploaded audio (${filename || 'unnamed'})`);
      tempPath = await saveBase64AudioToTemp(audioBase64, filename);
    } else {
      console.log(`🎵 Aligning lyrics for audio URL: ${audioUrl.substring(0, 80)}...`);
      tempPath = await downloadToTemp(audioUrl);
    }
    
    console.log(`📥 Audio ready at temp path: ${tempPath}`);
    
    const whisperJson = await runWhisper({ audioPath: tempPath, includeTokens: true, language: 'en', task: 'transcribe' });
    const segments = whisperJson?.segments || [];
    const tokens = whisperJson?.tokens || [];
    
    const aligned = alignLyricsToWhisper(plainLines, segments, tokens);
    const lines = aligned.lines || aligned.aligned || aligned;
    
    return res.json({ lines, confidence: aligned.confidence, anchors: aligned.anchors });
  } catch (error) {
    console.error('❌ Error in Whisper alignment:', error);
    res.status(500).json({ 
      error: 'Whisper alignment failed', 
      details: error.message 
    });
  } finally {
    if (tempPath) {
      try { await fsp.rm(tempPath, { force: true }); } catch (e) { /* ignore cleanup errors */ }
    }
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 YouTube Audio Server running on http://0.0.0.0:${PORT}`);
  console.log(`📱 Access from phone: http://192.168.1.133:${PORT}`);
  console.log(`📁 Downloads will be saved to: ${downloadsDir}`);
});
