#!/usr/bin/env python3
"""
Faster-whisper CLI wrapper that outputs in the same format as openai-whisper
Usage: python faster_whisper_cli.py <audio_file> --model <model> --output_dir <dir> --language <lang>
"""
import sys
import json
import argparse
from pathlib import Path
from faster_whisper import WhisperModel

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('audio', help='Audio file path')
    parser.add_argument('--model', default='base', help='Model size (tiny, base, small, medium, large)')
    parser.add_argument('--output_dir', required=True, help='Output directory')
    parser.add_argument('--language', default='en', help='Language code')
    parser.add_argument('--word_timestamps', default='True', help='Enable word timestamps')
    parser.add_argument('--output_format', default='json', help='Output format')
    
    args = parser.parse_args()
    
    # Load model (uses CPU by default, will use GPU if available)
    print(f"Loading faster-whisper model: {args.model}", file=sys.stderr)
    model = WhisperModel(args.model, device="cpu", compute_type="int8")
    
    # Transcribe
    print(f"Transcribing: {args.audio}", file=sys.stderr)
    segments, info = model.transcribe(
        args.audio,
        language=args.language,
        word_timestamps=True
    )
    
    # Convert to openai-whisper format
    result = {
        "text": "",
        "segments": [],
        "language": info.language
    }
    
    for segment in segments:
        seg_dict = {
            "id": len(result["segments"]),
            "start": segment.start,
            "end": segment.end,
            "text": segment.text,
            "words": []
        }
        
        if segment.words:
            for word in segment.words:
                seg_dict["words"].append({
                    "word": word.word,
                    "start": word.start,
                    "end": word.end
                })
        
        result["segments"].append(seg_dict)
        result["text"] += segment.text
    
    # Write output file
    output_path = Path(args.output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    audio_name = Path(args.audio).stem
    output_file = output_path / f"{audio_name}.json"
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    
    print(f"✅ Transcription complete: {len(result['segments'])} segments", file=sys.stderr)
    print(f"Output: {output_file}", file=sys.stderr)

if __name__ == '__main__':
    main()
