# ============================================================================
# System Resource Monitor - Multi-Stage Docker Build
# 
# This Dockerfile uses a multi-stage build to minimize the final image size.
# Stage 1: Builder - Compiles dependencies
# Stage 2: Runtime - Minimal image with only what's needed to run
# ============================================================================

# ----------------------------------------------------------------------------
# STAGE 1: Builder
# Uses full Python image with build tools to compile dependencies
# ----------------------------------------------------------------------------
FROM python:3.11-alpine AS builder

# Install build dependencies
# - gcc, musl-dev: Required to compile Python packages with C extensions
# - linux-headers: Required for psutil compilation
RUN apk add --no-cache \
    gcc \
    musl-dev \
    linux-headers \
    && rm -rf /var/cache/apk/*

# Install UV (fast Python package manager)
# We use UV instead of pip for faster installs in the container
RUN pip install --no-cache-dir uv

# Set working directory
WORKDIR /build

# Copy the build inputs. The package metadata names README.md as the readme
# and hatchling builds the wheel from src/system_monitor, so all three have
# to be in the build context before the install runs.
COPY pyproject.toml README.md ./
COPY src/ ./src/

# Create a virtual environment and install dependencies
# Using UV for faster installation.
#
# The install is deliberately not editable: an editable install resolves the
# package back to /build/src, which does not exist in the runtime stage, so
# the copied virtual environment would import nothing.
RUN uv venv /opt/venv && \
    uv pip install --python /opt/venv/bin/python .

# ----------------------------------------------------------------------------
# STAGE 2: Runtime
# Minimal image with only runtime dependencies
# ----------------------------------------------------------------------------
FROM python:3.11-alpine AS runtime

# Add metadata labels
LABEL maintainer="DevOps Capstone Project"
LABEL version="2.0.0"
LABEL description="Cross-Platform System Resource Monitor"

# Install runtime dependencies
# - procps: Provides ps command for process monitoring
# - coreutils: Basic utilities
RUN apk add --no-cache \
    procps \
    coreutils \
    && rm -rf /var/cache/apk/*

# Create non-root user for security
# Running as root in containers is a security risk
RUN addgroup -g 1000 monitor && \
    adduser -D -u 1000 -G monitor monitor

# Copy virtual environment from builder stage
COPY --from=builder /opt/venv /opt/venv

# Make virtual environment Python available
ENV PATH="/opt/venv/bin:$PATH"

# Set working directory
WORKDIR /app

# The working directory belongs to the unprivileged user, so the test profile
# can write its coverage data into it.
RUN chown monitor:monitor /app

# Copy application code
COPY --chown=monitor:monitor src/ ./src/

# Create logs directory with proper permissions
RUN mkdir -p /app/logs && chown monitor:monitor /app/logs

# Switch to non-root user
USER monitor

# Health check - verifies the application is working
# Docker will restart the container if this fails
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import psutil; psutil.cpu_percent(interval=1)" || exit 1

# Default command - show help
ENTRYPOINT ["python", "-m", "system_monitor"]
CMD ["--help"]

# ----------------------------------------------------------------------------
# STAGE 3: Test
# The runtime image plus the test dependencies, for the compose test profile.
# The production image stays lean, and the test profile builds this one.
# ----------------------------------------------------------------------------
FROM runtime AS test

USER root

# The virtual environment was created by uv, which does not seed it with pip,
# so ensurepip adds it. The test dependencies then go into the same
# interpreter the package lives in, and the suite runs against the installed
# package rather than the source tree.
RUN /opt/venv/bin/python -m ensurepip --upgrade && \
    /opt/venv/bin/python -m pip install --no-cache-dir pytest pytest-cov pytest-mock

USER monitor
