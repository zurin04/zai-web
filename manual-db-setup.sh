#!/bin/bash

# Manual Database Setup Script
# Use this if the main install script fails at database setup

set -e

echo "=== Manual Database Setup for Crypto Airdrop Platform ==="

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    echo "Starting PostgreSQL..."
    systemctl start postgresql
fi

# Create database and user
echo "Creating database and user..."
sudo -u postgres psql << 'EOF'
-- Drop existing database and user if they exist (optional)
-- DROP DATABASE IF EXISTS crypto_airdrop;
-- DROP USER IF EXISTS crypto_user;

-- Create database and user
CREATE DATABASE crypto_airdrop;
CREATE USER crypto_user WITH PASSWORD 'crypto_password_123';
GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop TO crypto_user;
ALTER USER crypto_user CREATEDB;
\q
EOF

# Create environment file
echo "Creating .env file..."
cat > .env << 'ENV_FILE'
DATABASE_URL=postgresql://crypto_user:crypto_password_123@localhost:5432/crypto_airdrop
PGHOST=localhost
PGPORT=5432
PGUSER=crypto_user
PGPASSWORD=crypto_password_123
PGDATABASE=crypto_airdrop
NODE_ENV=production
PORT=5000
SESSION_SECRET=your-secret-key-here-change-this-in-production
ENV_FILE

# Test database connection
echo "Testing database connection..."
export $(cat .env | xargs)
if PGPASSWORD=crypto_password_123 psql -h localhost -U crypto_user -d crypto_airdrop -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ Database connection successful"
else
    echo "❌ Database connection failed"
    exit 1
fi

# Create all tables manually (bypassing drizzle-kit)
echo "Creating database tables..."
PGPASSWORD=crypto_password_123 psql -h localhost -U crypto_user -d crypto_airdrop << 'SCHEMA_SQL'
-- Users table
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

-- Categories table
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT now() NOT NULL,
    updated_at TIMESTAMP DEFAULT now() NOT NULL
);

-- Airdrops table
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

-- Newsletters table
CREATE TABLE IF NOT EXISTS newsletters (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    subscribed_at TIMESTAMP DEFAULT now() NOT NULL
);

-- Announcements table
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

-- Creator applications table
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

-- Site settings table
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
SCHEMA_SQL

# Insert sample data
echo "Inserting sample data..."
PGPASSWORD=crypto_password_123 psql -h localhost -U crypto_user -d crypto_airdrop << 'SEED_SQL'
-- Insert admin user (password: admin123)
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
('Polygon zkEVM Testnet', 'Test the new Polygon zkEVM and earn early adopter rewards.', '["polygon", "zkevm", "testnet"]', 'https://polygon.technology', 1, 'admin'),
('Uniswap V4 Early Access', 'Get early access to Uniswap V4 features and earn rewards.', '["uniswap", "defi", "amm"]', 'https://uniswap.org', 1, 'admin')
ON CONFLICT DO NOTHING;

-- Insert site settings
INSERT INTO site_settings (id, site_name, site_description) VALUES 
(1, 'Crypto Airdrop Task Hub', 'Discover and track crypto airdrops, tasks, and rewards.')
ON CONFLICT (id) DO NOTHING;
SEED_SQL

echo "✅ Database setup completed successfully!"
echo ""
echo "Database Information:"
echo "  Database: crypto_airdrop"
echo "  User: crypto_user" 
echo "  Password: crypto_password_123"
echo "  Connection: postgresql://crypto_user:crypto_password_123@localhost:5432/crypto_airdrop"
echo ""
echo "Next steps:"
echo "1. Export environment variables: export \$(cat .env | xargs)"
echo "2. Install dependencies: npm install"
echo "3. Start application: npm run dev"
echo ""
echo "Login credentials:"
echo "  Admin: admin / admin123"
echo "  Demo: demo / demo123"