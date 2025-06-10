#!/bin/bash

# Crypto Airdrop Platform - Fixed VPS Installation
# This script fixes the database connection issues

set -e

echo "=== Crypto Airdrop Platform - Fixed Installation ==="
echo "Fixing database setup issues..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (or use sudo)"
    exit 1
fi

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y curl wget gnupg2 software-properties-common

# Install Node.js 20
echo "Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install PM2 for process management
echo "Installing PM2..."
npm install -g pm2

# Install Nginx
echo "Installing Nginx..."
apt install -y nginx

# Install PostgreSQL
if ! command -v psql &> /dev/null; then
    echo "Installing PostgreSQL..."
    apt install -y postgresql postgresql-contrib
    systemctl start postgresql
    systemctl enable postgresql
fi

# Create application directory
APP_DIR="/var/www/crypto-airdrop"
echo "Setting up application directory at $APP_DIR..."
mkdir -p $APP_DIR
cp -r . $APP_DIR/
cd $APP_DIR

# Set proper permissions
chown -R www-data:www-data $APP_DIR
chmod -R 755 $APP_DIR

# Install application dependencies
echo "Installing application dependencies..."
npm install

# Create database and user
echo "Setting up PostgreSQL database..."
sudo -u postgres psql -c "CREATE DATABASE crypto_airdrop;" || echo "Database already exists"
sudo -u postgres psql -c "CREATE USER crypto_user WITH PASSWORD 'crypto_password_123';" || echo "User already exists"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop TO crypto_user;"
sudo -u postgres psql -c "ALTER USER crypto_user CREATEDB;"

# Create proper environment file
echo "Creating environment configuration..."
cat > $APP_DIR/.env << EOF
# Database Configuration
DATABASE_URL=postgresql://crypto_user:crypto_password_123@localhost:5432/crypto_airdrop
PGHOST=localhost
PGPORT=5432
PGUSER=crypto_user
PGPASSWORD=crypto_password_123
PGDATABASE=crypto_airdrop

# Application Configuration
NODE_ENV=production
PORT=5000
SESSION_SECRET=$(openssl rand -base64 32)

# Security
BCRYPT_ROUNDS=12
EOF

# Set environment file permissions
chown www-data:www-data $APP_DIR/.env
chmod 600 $APP_DIR/.env

# Test database connection
echo "Testing database connection..."
export $(cat $APP_DIR/.env | xargs)
if ! psql $DATABASE_URL -c "SELECT 1;" > /dev/null 2>&1; then
    echo "Database connection failed. Checking configuration..."
    # Try alternative connection method
    PGPASSWORD=crypto_password_123 psql -h localhost -U crypto_user -d crypto_airdrop -c "SELECT 1;"
fi

# Set up database schema using direct SQL instead of drizzle push
echo "Setting up database schema..."
sudo -u postgres psql crypto_airdrop << 'EOSQL'
-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password TEXT,
    wallet_address TEXT UNIQUE,
    nonce TEXT,
    is_admin BOOLEAN DEFAULT false NOT NULL,
    is_creator BOOLEAN DEFAULT false NOT NULL,
    bio TEXT,
    saved_tasks JSONB DEFAULT '[]'::jsonb,
    completed_tasks JSONB DEFAULT '[]'::jsonb,
    twitter_handle TEXT,
    discord_handle TEXT,
    telegram_handle TEXT,
    profile_image TEXT,
    created_at TIMESTAMP DEFAULT now() NOT NULL
);

-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT now() NOT NULL,
    updated_at TIMESTAMP DEFAULT now() NOT NULL
);

-- Create airdrops table
CREATE TABLE IF NOT EXISTS airdrops (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    tags JSONB DEFAULT '[]'::jsonb,
    link TEXT,
    status TEXT DEFAULT 'active' NOT NULL,
    views INTEGER DEFAULT 0 NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    created_at TIMESTAMP DEFAULT now() NOT NULL,
    updated_at TIMESTAMP DEFAULT now() NOT NULL,
    posted_by TEXT NOT NULL
);

-- Create other tables
CREATE TABLE IF NOT EXISTS newsletters (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    subscribed_at TIMESTAMP DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS announcements (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    type TEXT DEFAULT 'info' NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    link TEXT,
    link_text TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT now() NOT NULL,
    updated_at TIMESTAMP DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS creator_applications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    status TEXT DEFAULT 'pending' NOT NULL,
    reason TEXT,
    payment_tx_hash TEXT,
    payment_amount TEXT,
    payment_currency TEXT,
    reviewed_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT now() NOT NULL,
    updated_at TIMESTAMP DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS site_settings (
    id SERIAL PRIMARY KEY,
    site_name TEXT DEFAULT 'Crypto Airdrop Task Hub' NOT NULL,
    site_description TEXT DEFAULT 'Discover and track crypto airdrops, tasks, and rewards.' NOT NULL,
    logo_url TEXT,
    banner_url TEXT,
    twitter_link TEXT,
    discord_link TEXT,
    telegram_link TEXT,
    creator_fee_currency TEXT DEFAULT 'USDT' NOT NULL,
    creator_fee_amount TEXT DEFAULT '10' NOT NULL,
    creator_payment_address TEXT,
    creator_payment_network TEXT DEFAULT 'Ethereum Mainnet',
    created_at TIMESTAMP DEFAULT now() NOT NULL,
    updated_at TIMESTAMP DEFAULT now() NOT NULL
);

-- Grant permissions to crypto_user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO crypto_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO crypto_user;
EOSQL

# Seed database with initial data
echo "Seeding database with initial data..."
sudo -u postgres psql crypto_airdrop << 'EOSQL'
-- Insert default admin user (password: admin123)
INSERT INTO users (username, password, is_admin, is_creator) VALUES 
('admin', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewBkuEdPzfqGULUi', true, true)
ON CONFLICT (username) DO NOTHING;

-- Insert demo user (password: demo123)
INSERT INTO users (username, password, is_admin, is_creator) VALUES 
('demo', '$2b$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', false, false)
ON CONFLICT (username) DO NOTHING;

-- Insert categories
INSERT INTO categories (name, description) VALUES 
('DeFi', 'Decentralized Finance protocols and airdrops'),
('Gaming', 'Blockchain gaming and NFT-related airdrops'),
('Mining', 'Airdrops related to mining and staking'),
('Exchange', 'Cryptocurrency exchange airdrops'),
('Social', 'Social media and community-based airdrops')
ON CONFLICT (name) DO NOTHING;

-- Insert sample airdrops
INSERT INTO airdrops (title, description, tags, link, category_id, posted_by) VALUES 
('Arbitrum Odyssey Rewards', 'Complete tasks on Arbitrum network to earn rewards and potential airdrop eligibility.', '["arbitrum", "layer2", "defi"]', 'https://arbitrum.io', 1, 'admin'),
('MetaMask Swap Rewards', 'Use MetaMask Swap feature to earn points and potential future rewards.', '["metamask", "swap", "ethereum"]', 'https://metamask.io', 1, 'admin'),
('Polygon zkEVM Testnet', 'Test the new Polygon zkEVM and earn early adopter rewards.', '["polygon", "zkevm", "testnet"]', 'https://polygon.technology', 1, 'admin')
ON CONFLICT DO NOTHING;

-- Insert site settings
INSERT INTO site_settings (id, site_name, site_description) VALUES 
(1, 'Crypto Airdrop Task Hub', 'Discover and track crypto airdrops, tasks, and rewards.')
ON CONFLICT (id) DO NOTHING;
EOSQL

# Create PM2 ecosystem file
echo "Creating PM2 configuration..."
cat > $APP_DIR/ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'crypto-airdrop',
    script: 'server/index.ts',
    interpreter: 'node',
    interpreter_args: '--loader tsx',
    cwd: '$APP_DIR',
    env: {
      NODE_ENV: 'production',
      PORT: 5000
    },
    env_file: '$APP_DIR/.env',
    instances: 1,
    exec_mode: 'fork',
    watch: false,
    max_memory_restart: '1G',
    error_file: '$APP_DIR/logs/err.log',
    out_file: '$APP_DIR/logs/out.log',
    log_file: '$APP_DIR/logs/combined.log',
    time: true
  }]
};
EOF

# Create logs directory
mkdir -p $APP_DIR/logs
chown -R www-data:www-data $APP_DIR/logs

# Configure Nginx
echo "Configuring Nginx..."
cat > /etc/nginx/sites-available/crypto-airdrop << EOF
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;
    
    client_max_body_size 10M;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    location /ws {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/crypto-airdrop /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
nginx -t

# Start services
echo "Starting services..."
systemctl reload nginx
systemctl enable nginx

# Start the application with PM2
cd $APP_DIR
export $(cat .env | xargs)
pm2 start ecosystem.config.js
pm2 save
pm2 startup

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "✅ PostgreSQL database created and seeded"
echo "✅ Application installed at: $APP_DIR"
echo "✅ Nginx configured and running"
echo "✅ PM2 process manager configured"
echo ""
echo "🌐 Your crypto airdrop platform is available at:"
echo "   http://$(curl -s ifconfig.me)"
echo "   http://localhost (if accessing locally)"
echo ""
echo "👤 Login credentials:"
echo "   Admin: admin / admin123"
echo "   Demo:  demo / demo123"
echo ""
echo "📊 Management commands:"
echo "   pm2 status                 - Check application status"
echo "   pm2 logs crypto-airdrop    - View application logs"
echo "   pm2 restart crypto-airdrop - Restart application"
echo "   systemctl status nginx     - Check nginx status"
echo ""
echo "🔧 Configuration files:"
echo "   Application: $APP_DIR"
echo "   Environment: $APP_DIR/.env"
echo "   Nginx: /etc/nginx/sites-available/crypto-airdrop"
echo ""