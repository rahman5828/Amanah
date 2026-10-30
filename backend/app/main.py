from fastapi import FastAPI

from app.api.routes.auth import router as auth_router
from app.api.routes.users import router as users_router

app = FastAPI(
    title="AMANAH API",
    description="Intelligence that cares.",
    version="0.1.0",
)

app.include_router(auth_router, prefix="/api/v1")
app.include_router(users_router, prefix="/api/v1")

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