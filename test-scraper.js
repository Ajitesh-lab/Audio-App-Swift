import { getVideoInfo } from './youtube-scraper.js';

// Test the scraper
const testVideoId = 'jNQXAC9IVRw'; // Short "Me at the zoo" video

console.log('Testing custom YouTube scraper...');
console.log('Video ID:', testVideoId);

try {
  const info = await getVideoInfo(testVideoId);
  console.log('\n✅ Success!');
  console.log('Title:', info.title);
  console.log('Author:', info.author);
  console.log('Duration:', info.duration, 'seconds');
  console.log('Audio URL length:', info.audioUrl.length, 'chars');
  console.log('Audio Quality:', info.audioQuality);
  console.log('\nFirst 100 chars of URL:', info.audioUrl.substring(0, 100));
} catch (error) {
  console.error('\n❌ Error:', error.message);
  console.error('Stack:', error.stack);
}
