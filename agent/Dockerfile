FROM python:3.14-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.36.4/bin/linux/amd64/kubectl \
 && chmod +x /usr/local/bin/kubectl \
 && apt-get purge -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir google-adk==2.15.0 pandas==3.1.1 k8s-agent-sandbox==0.1.1.post3
COPY root_agent /app/root_agent
EXPOSE 8080
ENTRYPOINT ["adk", "web", "--host", "0.0.0.0", "--port", "8080"]
