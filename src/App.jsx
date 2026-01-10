import React, { useState, useRef, useEffect } from 'react';
import { Play, Pause, Home, Library, Upload, Trash2 } from 'lucide-react';

function App() {
  const [currentView, setCurrentView] = useState('home');
  const [currentSong, setCurrentSong] = useState(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [localFiles, setLocalFiles] = useState([]);
  
  const audioRef = useRef(null);
  const fileInputRef = useRef(null);

  useEffect(() => {
    audioRef.current = new Audio();
    return () => {
      if (audioRef.current) audioRef.current.pause();
    };
  }, []);

  const togglePlay = () => {
    if (!audioRef.current || !currentSong) return;
    if (isPlaying) {
      audioRef.current.pause();
    } else {
      audioRef.current.play();
    }
    setIsPlaying(!isPlaying);
  };

  const playSong = (song) => {
    if (!audioRef.current) return;
    setCurrentSong(song);
    audioRef.current.src = song.url;
    audioRef.current.play();
    setIsPlaying(true);
  };

  const handleFileUpload = (e) => {
    const files = Array.from(e.target.files);
    files.forEach(file => {
      if (file.type.startsWith('audio/')) {
        const newSong = {
          id: Date.now() + Math.random(),
          title: file.name.replace(/\.[^/.]+$/, ''),
          url: URL.createObjectURL(file)
        };
        setLocalFiles(prev => [...prev, newSong]);
      }
    });
  };

  return (
    <div className="flex h-screen bg-black text-white">
      <aside className="w-64 bg-black border-r border-gray-800 p-6">
        <h1 className="text-2xl font-bold mb-8">Music Player</h1>
        <nav className="space-y-4">
          <button onClick={() => setCurrentView('home')} className="flex items-center gap-3 w-full p-3 rounded-lg hover:bg-gray-800">
            <Home size={20} />
            <span>Home</span>
          </button>
          <button onClick={() => setCurrentView('library')} className="flex items-center gap-3 w-full p-3 rounded-lg hover:bg-gray-800">
            <Library size={20} />
            <span>Library</span>
          </button>
          <button onClick={() => fileInputRef.current?.click()} className="flex items-center gap-3 w-full p-3 rounded-lg hover:bg-gray-800">
            <Upload size={20} />
            <span>Upload</span>
          </button>
          <input ref={fileInputRef} type="file" accept="audio/*" multiple onChange={handleFileUpload} className="hidden" />
        </nav>
      </aside>

      <main className="flex-1 overflow-y-auto pb-32">
        {currentView === 'home' && (
          <div className="p-8">
            <h2 className="text-3xl font-bold mb-6">Welcome</h2>
            <p className="text-gray-400">Upload audio files to get started.</p>
          </div>
        )}

        {currentView === 'library' && (
          <div className="p-8">
            <h2 className="text-3xl font-bold mb-6">Library</h2>
            {localFiles.length === 0 ? (
              <p className="text-gray-400">No songs yet.</p>
            ) : (
              <div className="space-y-2">
                {localFiles.map(song => (
                  <div key={song.id} onClick={() => playSong(song)} className="flex items-center gap-4 p-3 rounded-lg hover:bg-gray-800 cursor-pointer">
                    <p className="flex-1 font-medium">{song.title}</p>
                    <button onClick={(e) => { e.stopPropagation(); setLocalFiles(localFiles.filter(f => f.id !== song.id)); }} className="p-2 hover:bg-gray-700 rounded">
                      <Trash2 size={16} />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </main>

      <div className="fixed bottom-0 left-0 right-0 bg-gray-900 border-t border-gray-800 px-4 py-3">
        <div className="flex items-center justify-center gap-4">
          <div className="flex-1">
            <p className="font-medium">{currentSong ? currentSong.title : 'No song playing'}</p>
          </div>
          <button onClick={togglePlay} disabled={!currentSong} className="w-10 h-10 bg-white text-black rounded-full flex items-center justify-center disabled:opacity-30">
            {isPlaying ? <Pause size={20} /> : <Play size={20} />}
          </button>
        </div>
      </div>
    </div>
  );
}

export default App;
