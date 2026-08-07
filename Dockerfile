FROM python:3.13-slim

WORKDIR /app

# Build tools only needed transiently for a couple of source deps' wheels;
# stripped from the final layer via apt purge to keep the image small.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn==23.0.0 \
    && apt-get purge -y --auto-remove build-essential

COPY . .

# Single operator, single in-memory RUN_STATE dict (app.py) — deliberately
# NOT scaled to multiple worker processes, since state isn't shared across
# processes. --threads lets it serve the background-job polling routes
# (/job_status etc.) concurrently with an in-flight request, same as the
# dev server's default threading.
RUN useradd --create-home specgen \
    && chown -R specgen:specgen /app
USER specgen

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "8", \
     "--timeout", "300", "app:app"]
