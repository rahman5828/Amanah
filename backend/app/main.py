from fastapi import FastAPI

app = FastAPI(
    title="AMANAH API",
    description="Intelligence that cares.",
    version="0.1.0",
)


@app.get("/")
async def root():
    return {
        "application": "AMANAH",
        "message": "Intelligence that cares.",
        "status": "running",
        "version": "0.1.0",
    }


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "amanah-backend",
    }