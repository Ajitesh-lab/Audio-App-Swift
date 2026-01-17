FROM node:18-slim

# Install system dependencies including build tools for native modules
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    build-essential \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install faster-whisper and download tools (yt-dlp primary, youtube-dl fallback)
RUN pip3 install --no-cache-dir --break-system-packages faster-whisper yt-dlp youtube-dl

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies and rebuild native modules
RUN npm install

# Copy server files (excluding node_modules from host)
COPY auth.js server.js ./
COPY utils ./utils

# Create directories
RUN mkdir -p /app/downloads /app/alignments

# Expose port
EXPOSE 3001

# Start server
CMD ["node", "server.js"]
