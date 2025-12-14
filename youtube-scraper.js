import axios from 'axios';

/**
 * Custom YouTube audio scraper - no external tools, pure JavaScript
 */

// Extract video ID from various YouTube URL formats
export function extractVideoId(url) {
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([^&\n?#]+)/,
    /^([a-zA-Z0-9_-]{11})$/
  ];
  
  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match) return match[1];
  }
  return null;
}

// Fetch YouTube page and extract player response
async function getPlayerResponse(videoId) {
  try {
    const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;
    console.log(`🔍 Fetching video page: ${videoId}`);
    
    const response = await axios.get(videoUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9'
      }
    });
    
    const html = response.data;
    
    // Extract ytInitialPlayerResponse JSON from page
    const playerResponseMatch = html.match(/var ytInitialPlayerResponse = ({.+?});/);
    if (!playerResponseMatch) {
      throw new Error('Could not find player response in page');
    }
    
    const playerResponse = JSON.parse(playerResponseMatch[1]);
    return playerResponse;
    
  } catch (error) {
    console.error('❌ Failed to get player response:', error.message);
    throw error;
  }
}

// Decipher signature cipher
function decipherSignature(html, signatureCipher) {
  try {
    // Parse the cipher
    const params = new URLSearchParams(signatureCipher);
    const url = params.get('url');
    const s = params.get('s');
    const sp = params.get('sp') || 'sig';
    
    if (!url || !s) {
      throw new Error('Missing URL or signature in cipher');
    }
    
    // Extract player code URL from page
    const playerMatch = html.match(/"jsUrl":"([^"]+)"/);
    if (!playerMatch) {
      throw new Error('Could not find player code URL');
    }
    
    // For now, return URL without signature (will fail but shows we're close)
    console.warn('⚠️  Signature cipher detected - this requires player code execution');
    console.warn('    Returning URL without signature - may not work');
    
    return url;
    
  } catch (error) {
    console.error('❌ Failed to decipher signature:', error.message);
    throw error;
  }
}

// Extract audio formats from player response
function getAudioFormats(playerResponse, html) {
  try {
    const streamingData = playerResponse.streamingData;
    if (!streamingData) {
      throw new Error('No streaming data found');
    }
    
    // Combine adaptive formats (usually better quality)
    const formats = streamingData.adaptiveFormats || [];
    
    // Filter for audio-only formats
    const audioFormats = formats.filter(format => 
      format.mimeType && format.mimeType.includes('audio')
    );
    
    if (audioFormats.length === 0) {
      throw new Error('No audio formats found');
    }
    
    // Sort by quality (higher bitrate = better)
    audioFormats.sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0));
    
    // Decipher if needed
    for (const format of audioFormats) {
      if (!format.url && format.signatureCipher) {
        format.url = decipherSignature(html, format.signatureCipher);
      }
    }
    
    return audioFormats;
    
  } catch (error) {
    console.error('❌ Failed to extract formats:', error.message);
    throw error;
  }
}

// Get video info and audio URL
export async function getVideoInfo(videoId) {
  try {
    console.log(`📹 Getting info for: ${videoId}`);
    const startTime = Date.now();
    
    // Get both player response and HTML (need HTML for signature deciphering)
    const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;
    const response = await axios.get(videoUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9'
      }
    });
    
    const html = response.data;
    
    // Extract player response
    const playerResponseMatch = html.match(/var ytInitialPlayerResponse = ({.+?});/);
    if (!playerResponseMatch) {
      throw new Error('Could not find player response in page');
    }
    
    const playerResponse = JSON.parse(playerResponseMatch[1]);
    
    // Extract video details
    const videoDetails = playerResponse.videoDetails;
    if (!videoDetails) {
      throw new Error('No video details found');
    }
    
    // Get audio formats (pass HTML for signature deciphering)
    const audioFormats = getAudioFormats(playerResponse, html);
    const bestAudio = audioFormats[0];
    
    if (!bestAudio.url) {
      throw new Error('Audio format has no direct URL even after deciphering');
    }
    
    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`✅ Got video info in ${duration}s`);
    
    return {
      videoId: videoDetails.videoId,
      title: videoDetails.title,
      author: videoDetails.author,
      duration: parseInt(videoDetails.lengthSeconds),
      thumbnail: videoDetails.thumbnail?.thumbnails[0]?.url,
      audioUrl: bestAudio.url,
      audioBitrate: bestAudio.bitrate,
      audioQuality: bestAudio.audioQuality,
      mimeType: bestAudio.mimeType
    };
    
  } catch (error) {
    console.error('❌ Failed to get video info:', error.message);
    throw error;
  }
}

// Download audio stream to buffer
export async function downloadAudio(audioUrl) {
  try {
    console.log(`⬇️  Downloading audio stream...`);
    const startTime = Date.now();
    
    const response = await axios.get(audioUrl, {
      responseType: 'stream',
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }
    });
    
    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`✅ Audio stream ready in ${duration}s`);
    
    return response.data;
    
  } catch (error) {
    console.error('❌ Failed to download audio:', error.message);
    throw error;
  }
}
