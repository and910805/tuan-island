FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --gid 10001 island \
    && useradd --uid 10001 --gid island --no-create-home island \
    && install -d -o island -g island /data
COPY app.py identity_store.py serve.py admin.py ./
USER 10001:10001
EXPOSE 8081/tcp
ENTRYPOINT ["python", "/app/serve.py", "--database", "/data/identity.sqlite", "--host", "0.0.0.0", "--port", "8081"]
