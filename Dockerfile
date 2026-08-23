# syntax=docker/dockerfile:1
# check=error=true

# One image, three roles — web (Puma), jobs (Solid Queue) and player (mpv):
#
#   docker compose up -d          # the supported way, see docs/DOCKER.md
#   docker build -t party .       # by hand
#
# The image carries mpv, ffmpeg and yt-dlp because the player and job containers
# shell out to them.

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.10
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages.
#   mpv      — playback (the player container drives it over a JSON IPC socket)
#   ffmpeg   — EBU R128 loudness measurement (LoudnessAnalyzer)
#   libpulse0/libasound2 — mpv's routes to the host's audio (see docs/DOCKER.md)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl ca-certificates libjemalloc2 libvips postgresql-client \
      mpv ffmpeg libpulse0 libasound2 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# yt-dlp: the Debian package lags behind YouTube's changes badly enough to break
# downloading, so take the self-contained upstream build. Pin by setting
# YT_DLP_VERSION to a release tag (e.g. 2025.06.30) for a reproducible image.
ARG YT_DLP_VERSION=latest
RUN case "$YT_DLP_VERSION" in \
      latest) url="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux" ;; \
      *)      url="https://github.com/yt-dlp/yt-dlp/releases/download/${YT_DLP_VERSION}/yt-dlp_linux" ;; \
    esac && \
    curl -fsSL "$url" -o /usr/local/bin/yt-dlp && chmod 0755 /usr/local/bin/yt-dlp && \
    /usr/local/bin/yt-dlp --version

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user. The uid MUST match the
# owner of the host's PulseAudio socket (i.e. the desktop user) for audio to
# work — that is why it is a build arg rather than a hard-coded 1000.
ARG PUID=1000
ARG PGID=1000
RUN groupadd --system --gid $PGID rails && \
    useradd rails --uid $PUID --gid $PGID --create-home --shell /bin/bash

# Copy built artifacts: gems, application
COPY --chown=$PUID:$PGID --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=$PUID:$PGID --from=build /rails /rails

# Mount points and writable state. /data is a volume in compose: the cache holds
# downloaded YouTube audio (its absolute path is stored in the DB, so keep it
# stable) and /data/run holds the mpv IPC socket.
RUN mkdir -p /music /data/cache /data/run && \
    chown -R $PUID:$PGID /data /rails/tmp /rails/log /rails/storage

ENV PARTY_MUSIC_DIR="/music" \
    PARTY_CACHE_DIR="/data/cache" \
    PARTY_MPV_SOCKET="/data/run/party-mpv.sock" \
    PORT="3000"

USER $PUID:$PGID

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server"]
