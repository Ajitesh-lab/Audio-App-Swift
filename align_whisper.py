#!/usr/bin/env python3
"""
Lightweight alignment script using open-source Whisper and optionally WhisperX.
Usage:
  python align_whisper.py /path/to/audio.mp3 "lyrics line 1\nlyrics line 2"

Outputs JSON array of {line, start, end} to stdout.

Notes:
- If `whisperx` is installed, it will be used to get word-level timestamps and better alignment.
- If only `whisper` is installed, we'll use segment timestamps and map lyric lines to segments heuristically.
"""
import sys
import json
import tempfile
import os
import ssl
# Fix SSL certificate issues for model downloads
ssl._create_default_https_context = ssl._create_unverified_context

def normalize_text(text):
    """Normalize text for comparison"""
    import re
    text = text.lower()
    text = re.sub(r'[^\w\s]', '', text)  # Remove punctuation
    text = re.sub(r'\s+', ' ', text)  # Normalize whitespace
    return text.strip()

def word_similarity(w1, w2):
    """Calculate similarity between two words (0-1)"""
    w1, w2 = w1.lower(), w2.lower()
    if w1 == w2:
        return 1.0
    # Simple character overlap ratio
    chars1, chars2 = set(w1), set(w2)
    if not chars1 or not chars2:
        return 0.0
    return len(chars1 & chars2) / len(chars1 | chars2)

def fallback_align(transcript_segments, lyrics_lines):
    """Align lyrics to transcript segments using dynamic programming"""
    results = []
    
    # Build word-level timeline from segments
    words_timeline = []
    for seg in transcript_segments:
        seg_words = normalize_text(seg['text']).split()
        if not seg_words:
            continue
        seg_duration = seg['end'] - seg['start']
        time_per_word = seg_duration / len(seg_words)
        for i, word in enumerate(seg_words):
            word_start = seg['start'] + (i * time_per_word)
            word_end = word_start + time_per_word
            words_timeline.append({
                'word': word,
                'start': word_start,
                'end': word_end
            })
    
    if not words_timeline:
        # No transcription, return empty timestamps
        return [{'line': l, 'start': None, 'end': None} for l in lyrics_lines]
    
    # Find where the actual lyrics start by matching first few lyric lines
    # This skips intros, pre-song dialogue, etc.
    start_offset = 0
    first_few_lyrics = ' '.join([normalize_text(l) for l in lyrics_lines[:3] if l.strip()])
    best_start_score = 0
    best_start_pos = 0
    
    for start_idx in range(min(50, len(words_timeline))):
        test_window = ' '.join([words_timeline[start_idx + i]['word'] for i in range(min(15, len(words_timeline) - start_idx))])
        # Simple word overlap score
        score = sum(1 for word in first_few_lyrics.split() if word in test_window)
        if score > best_start_score:
            best_start_score = score
            best_start_pos = start_idx
    
    # Start alignment from the best match position
    current_pos = best_start_pos
    for line in lyrics_lines:
        l = line.strip()
        if not l:
            results.append({'line': '', 'start': None, 'end': None})
            continue
        
        lyric_words = normalize_text(l).split()
        if not lyric_words:
            results.append({'line': l, 'start': None, 'end': None})
            continue
        
        # Find best matching position in timeline for this line
        best_score = 0
        best_start_idx = current_pos
        
        # Search forward from current position
        for start_idx in range(current_pos, min(current_pos + 50, len(words_timeline))):
            if start_idx + len(lyric_words) > len(words_timeline):
                break
            
            # Calculate match score for this position
            score = 0
            for i, lyric_word in enumerate(lyric_words):
                if start_idx + i < len(words_timeline):
                    transcript_word = words_timeline[start_idx + i]['word']
                    score += word_similarity(lyric_word, transcript_word)
            
            if score > best_score:
                best_score = score
                best_start_idx = start_idx
        
        # Use the best match position
        if best_start_idx < len(words_timeline):
            start_time = words_timeline[best_start_idx]['start']
            end_idx = min(best_start_idx + len(lyric_words) - 1, len(words_timeline) - 1)
            end_time = words_timeline[end_idx]['end']
            results.append({'line': l, 'start': start_time, 'end': end_time})
            current_pos = end_idx + 1
        else:
            # Fallback if we run out of timeline
            if results and results[-1]['end'] is not None:
                last_end = results[-1]['end']
                results.append({'line': l, 'start': last_end, 'end': last_end + 2.0})
            else:
                # Use last known time or default to 0
                last_time = results[-1]['start'] if results and results[-1]['start'] is not None else 0.0
                results.append({'line': l, 'start': last_time, 'end': last_time + 2.0})
    
    return results

def main():
    if len(sys.argv) < 3:
        print('Usage: align_whisper.py /path/to/audio.mp3 "lyrics here (\n separated)"', file=sys.stderr)
        sys.exit(2)

    audio_path = sys.argv[1]
    lyrics_text = sys.argv[2]
    
    # Debug: Log what we received
    print(f"DEBUG: Received lyrics text length: {len(lyrics_text)}", file=sys.stderr)
    print(f"DEBUG: First 200 chars: {repr(lyrics_text[:200])}", file=sys.stderr)
    print(f"DEBUG: Contains \\n: {'\\n' in lyrics_text}", file=sys.stderr)
    print(f"DEBUG: Contains literal backslash-n: {'\\\\n' in lyrics_text}", file=sys.stderr)
    
    lyrics_lines = lyrics_text.split('\n')
    print(f"DEBUG: Split into {len(lyrics_lines)} lines", file=sys.stderr)
    
    # If no lyrics provided, do pure transcription
    if not lyrics_text.strip() or lyrics_text.strip() == '':
        lyrics_lines = []
    
    # Suppress warnings globally
    import warnings
    warnings.filterwarnings('ignore')
    
    # Use openai-whisper (faster-whisper has compatibility issues on M4)
    import whisper
    
    try:
        import torch
        device = "cpu"  # MPS causes issues, stick with CPU for stability
    except:
        device = "cpu"
    
    print(f"Using openai-whisper medium model with device={device}", file=sys.stderr)
    model = whisper.load_model('medium', device=device)
    result = model.transcribe(audio_path)
    transcript_segments = result['segments']
    
    # If no lyrics provided, return pure transcription
    if not lyrics_lines or len(lyrics_lines) == 0 or all(not l.strip() for l in lyrics_lines):
        pure_transcript = [{'line': seg['text'].strip(), 'start': seg['start'], 'end': seg['end']} 
                          for seg in transcript_segments if seg.get('text', '').strip()]
        print(json.dumps(pure_transcript))
        sys.exit(0)
    
    # Align lyrics to transcript
    mapped = fallback_align(transcript_segments, lyrics_lines)
    print(json.dumps(mapped))
    sys.exit(0)

if __name__ == '__main__':
    main()
