import { basename } from 'path';

// ---------- Timestamp Helpers ----------
export const parseTimestampToSeconds = (ts) => {
  // Supports [mm:ss.xx] or [mm:ss.xxx]
  const match = ts.match(/(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?/);
  if (!match) return null;
  const minutes = parseInt(match[1], 10);
  const seconds = parseInt(match[2], 10);
  const millis = match[3] ? parseInt(match[3].padEnd(3, '0'), 10) : 0;
  return minutes * 60 + seconds + millis / 1000;
};

export const formatSecondsToTimestamp = (value, precision = 2) => {
  const clamped = Math.max(0, value);
  const minutes = Math.floor(clamped / 60);
  const seconds = Math.floor(clamped % 60);
  const frac = clamped - Math.floor(clamped);
  const rounded = Math.round(frac * Math.pow(10, precision));
  const fraction = (rounded / Math.pow(10, precision)).toFixed(precision).split('.')[1];
  return `[${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}.${fraction}]`;
};

// ---------- LRC Parsing/Shifting ----------
export const parseLrc = (lrcText) => {
  const lines = lrcText.split(/\r?\n/);
  const tags = [];
  const entries = [];
  for (const line of lines) {
    const tagMatch = line.match(/^\[(ti|ar|al|by|offset):(.+)\]$/i);
    if (tagMatch) {
      tags.push(line);
      continue;
    }
    const match = line.match(/^\[(\d{1,2}:\d{2}(?:\.\d{1,3})?)\](.*)$/);
    if (!match) continue;
    const time = parseTimestampToSeconds(match[1]);
    const text = match[2]?.trim() || '';
    if (time !== null) {
      entries.push({ time, text, raw: line });
    }
  }
  return { tags, entries };
};

export const parseFirstLrcTime = (lrcText) => {
  const { entries } = parseLrc(lrcText);
  const first = entries.find(e => e.text && e.text.length > 0);
  return first ? first.time : null;
};

export const shiftLrc = (lrcText, offsetSeconds, options = {}) => {
  const precision = options.precision ?? 2;
  const floor = options.floor ?? 0;
  const { tags, entries } = parseLrc(lrcText);
  const shifted = entries.map(entry => {
    const shiftedTime = Math.max(floor, entry.time + offsetSeconds);
    const ts = formatSecondsToTimestamp(shiftedTime, precision);
    return `${ts} ${entry.text}`.trimEnd();
  });
  return [...tags, ...shifted].join('\n');
};

// ---------- Vocal Detection ----------
export const detectFirstVocal = (segments, opts = {}) => {
  const minDuration = opts.minDuration ?? 0.4;
  const maxNoSpeech = opts.maxNoSpeech ?? 0.5;
  const minLogProb = opts.minLogProb ?? -2.0;
  const valid = segments
    .filter(seg => seg && typeof seg.start === 'number' && typeof seg.end === 'number')
    .filter(seg => (seg.end - seg.start) >= minDuration)
    .filter(seg => seg.no_speech_prob === undefined || seg.no_speech_prob <= maxNoSpeech)
    .filter(seg => seg.avg_logprob === undefined || seg.avg_logprob >= minLogProb);
  if (!valid.length) return null;
  return Math.min(...valid.map(s => s.start));
};

export const computeOffset = (firstVocal, firstLrcTime) => {
  if (firstVocal === null || firstVocal === undefined) return null;
  if (firstLrcTime === null || firstLrcTime === undefined) return null;
  return firstVocal - firstLrcTime;
};

// ---------- Text Normalization ----------
export const normalizeText = (text) =>
  (text || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s']/g, '')
    .replace(/\s+/g, ' ')
    .trim();

const tokenize = (text) => normalizeText(text).split(' ').filter(Boolean);

const jaccard = (aTokens, bTokens) => {
  const aSet = new Set(aTokens);
  const bSet = new Set(bTokens);
  const intersection = [...aSet].filter(x => bSet.has(x)).length;
  const union = new Set([...aTokens, ...bTokens]).size || 1;
  return intersection / union;
};

const ratioNonLatin = (text) => {
  const total = text.length || 1;
  // Check for non-Latin characters (simpler pattern for older Node versions)
  const nonLatin = (text.match(/[^a-zA-Z\s\d]/g) || []).length;
  return nonLatin / total;
};

// ---------- Alignment (simple segment-based like old system) ----------
export const alignLyricsToWhisper = (plainLines, whisperSegments, whisperTokens = []) => {
  const lines = plainLines.map(line => line.trim()).filter(Boolean).map(line => ({
    raw: line,
    tokens: tokenize(line)
  }));

  const segments = (whisperSegments || [])
    .filter(seg => seg && typeof seg.start === 'number' && typeof seg.end === 'number')
    .map(seg => ({
      ...seg,
      tokens: tokenize(seg.text || ''),
      duration: seg.end - seg.start
    }));

  if (!segments.length) {
    // No segments, return empty
    return {
      lrc: '',
      confidence: 0,
      lineConfidences: [],
      lines: lines.map(l => ({ line: l.raw, start: null, end: null })),
      anchors: [],
      offset: 0
    };
  }

  // Auto-detect offset using first vocal detection (reliable method)
  let detectedOffset = 0;
  console.log(`🔍 Offset detection: lines=${lines.length}, segments=${segments.length}`);

  // Use detectFirstVocal to find when singing actually starts
  const firstVocalTime = detectFirstVocal(segments, {
    minDuration: 0.5,
    maxNoSpeech: 0.3,
    minLogProb: -1.5
  });

  if (firstVocalTime !== null) {
    // Assume lyrics start at or near the first vocal
    detectedOffset = firstVocalTime;
    console.log(`🎯 Auto-detected offset: ${detectedOffset.toFixed(2)}s (first vocal detected)`);
  } else {
    console.log(`⚠️ No clear first vocal detected, using 0 offset`);
  }

  const results = [];
  let segIndex = 0;

  // Simple greedy alignment: consume segments for each lyric line
  lines.forEach((line, idx) => {
    if (segIndex >= segments.length) {
      // Out of segments, estimate
      const lastResult = results[results.length - 1];
      const start = lastResult ? lastResult.end : 0;
      results.push({ line: line.raw, start, end: start + 2, confidence: 0.3 });
      return;
    }

    const targetWords = Math.max(line.tokens.length, 1);
    let collected = [];
    let wordCount = 0;
    let bestMatchIdx = segIndex;
    let bestConfidence = 0;

    // Look ahead up to 3 segments to find best match, then consume only those needed
    const lookahead = Math.min(5, segments.length - segIndex);
    for (let i = 0; i < lookahead; i++) {
      const testIdx = segIndex + i;
      const testSeg = segments[testIdx];
      const testTokens = testSeg.tokens;
      const conf = jaccard(line.tokens, testTokens);
      
      // If this segment matches well on its own, use just this one
      if (conf > bestConfidence) {
        bestConfidence = conf;
        bestMatchIdx = testIdx;
      }
      
      // If we found a good match (>0.3), stop looking
      if (conf > 0.3) break;
    }

    // Collect just the best matching segment(s)
    // If line is short (<=3 words), use 1 segment
    // Otherwise, collect segments until we have roughly the right word count
    if (targetWords <= 3 || bestConfidence > 0.3) {
      // Use just the best segment
      const seg = segments[bestMatchIdx];
      collected = [seg];
      segIndex = bestMatchIdx + 1;
      wordCount = seg.tokens.length || 1;
    } else {
      // Collect multiple segments for longer lines
      while (segIndex < segments.length && wordCount < targetWords) {
        const seg = segments[segIndex];
        collected.push(seg);
        wordCount += seg.tokens.length || 1;
        segIndex += 1;
        
        // Stop once we have enough words (don't overshoot)
        if (wordCount >= targetWords * 0.9) break;
      }
    }

    if (!collected.length) {
      const lastResult = results[results.length - 1];
      const start = lastResult ? lastResult.end : 0;
      results.push({ line: line.raw, start, end: start + 1.5, confidence: 0.3 });
      return;
    }

    const start = collected[0].start;
    const end = collected[collected.length - 1].end;
    const collectedTokens = collected.flatMap(c => c.tokens);
    const confidence = jaccard(line.tokens, collectedTokens);

    results.push({ line: line.raw, start, end, confidence });
  });

  // Interpolate any missing times
  const finalLines = results.map((r, i, arr) => {
    if (r.start !== null && r.end !== null) return r;
    
    // Find neighbors with valid times
    const prev = [...arr.slice(0, i)].reverse().find(x => x.start !== null);
    const next = arr.slice(i + 1).find(x => x.start !== null);
    
    if (prev && next) {
      const gap = next.start - prev.end;
      const prevIdx = arr.indexOf(prev);
      const nextIdx = arr.indexOf(next);
      const portion = (i - prevIdx) / (nextIdx - prevIdx);
      const start = prev.end + gap * portion;
      const end = start + Math.max(1.5, gap * 0.3);
      return { ...r, start, end, confidence: r.confidence * 0.5 };
    }
    
    if (prev) {
      const start = prev.end + 0.5;
      const end = start + 2;
      return { ...r, start, end, confidence: r.confidence * 0.4 };
    }
    
    if (next) {
      const start = Math.max(0, next.start - 2);
      const end = next.start - 0.2;
      return { ...r, start, end, confidence: r.confidence * 0.4 };
    }
    
    return r;
  });

  // Enforce monotonic timestamps
  let prev = 0;
  const monotonic = finalLines.map(r => {
    const start = Math.max(prev + 0.05, r.start ?? prev + 0.05);
    const end = Math.max(start + 0.5, r.end ?? start + 1.5);
    prev = end;
    return { ...r, start, end };
  });

  const lrc = monotonic
    .map(r => `${formatSecondsToTimestamp(r.start, 2)} ${r.line}`)
    .join('\n');

  const avgConfidence =
    monotonic.reduce((sum, r) => sum + (r.confidence || 0), 0) / (monotonic.length || 1);

  return {
    lrc,
    confidence: Number(avgConfidence.toFixed(3)),
    lineConfidences: monotonic.map(r => Number((r.confidence || 0).toFixed(3))),
    lines: monotonic,
    anchors: [],
    offset: 0  // NO GLOBAL OFFSET - Whisper timestamps are used directly
  };
};

// ---------- Utility to describe file names for logs ----------
export const describeAudio = (audioPath) => basename(audioPath || '');
