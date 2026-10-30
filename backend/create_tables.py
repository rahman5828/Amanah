from app.core.database import engine
from app.models import Base

Base.metadata.create_all(bind=engine)

print("AMANAH DATABASE TABLES CREATED!")
