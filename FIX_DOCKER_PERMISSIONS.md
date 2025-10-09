# Fix Docker Permission Issues

## Problem

You're seeing this error:
```
failed to stop container: Error response from daemon: cannot stop container:
edad6ec42bd60d015fc5bf3d225f8a1798a206dbc316112f5e3d08f24997b901: permission denied
```

This happens when Docker containers are created with root ownership.

## Solution

### Option 1: Stop Containers Manually (Recommended)

```bash
# Check running containers
docker ps -a | grep supabase

# Stop and remove the problematic container
docker stop supabase_db_GiftCircles
docker rm supabase_db_GiftCircles

# Or stop all supabase containers
docker stop $(docker ps -q --filter "name=supabase")
docker rm $(docker ps -aq --filter "name=supabase")
```

### Option 2: Use Docker Group (Preferred Long-term Fix)

```bash
# Add your user to the docker group
sudo usermod -aG docker $USER

# Apply group changes (or log out and back in)
newgrp docker

# Verify docker works without sudo
docker ps
```

### Option 3: Clean Start

```bash
# Remove all Supabase containers and volumes
docker stop $(docker ps -q --filter "name=supabase") 2>/dev/null || true
docker rm $(docker ps -aq --filter "name=supabase") 2>/dev/null || true
docker volume prune -f

# Start fresh
cd /home/chris/Documents/Repos/GiftCircles
supabase start
```

## After Fixing Permissions

Once you've fixed the Docker permissions, start Supabase:

```bash
cd /home/chris/Documents/Repos/GiftCircles
supabase start
```

The migrations will run in this order:
1. `000_initial_schema.sql` - Creates all tables (NEW - I just created this)
2. `001_force_rls_security.sql` - Enables FORCE RLS
3. `002` through `017` - All your feature migrations

## Verify It Works

```bash
# Check migrations ran
supabase db diff --schema public

# Run tests
psql $(supabase status | grep "DB URL" | awk '{print $3}') \
  -f supabase/tests/run_all_tests.sql
```

## If You Still Have Issues

### Check Docker Service Status
```bash
systemctl status docker
sudo systemctl start docker
```

### Check Docker Permissions
```bash
ls -la /var/run/docker.sock
# Should show: srw-rw---- 1 root docker

# If not in docker group:
groups $USER
# Should show: ... docker ...
```

### Nuclear Option (Last Resort)
```bash
# This will remove ALL Docker containers and volumes
docker system prune -a --volumes
supabase start
```

## Why This Happened

The Supabase CLI creates Docker containers, and if you ran it with `sudo` at some point, those containers were created with root ownership. This prevents the non-root CLI from managing them.

## Prevention

Always run Supabase CLI commands as your regular user (not with sudo):
```bash
# ✅ Good
supabase start
supabase db reset

# ❌ Bad
sudo supabase start
sudo supabase db reset
```
