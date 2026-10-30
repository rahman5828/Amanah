from sqlalchemy import text

from app.core.database import engine

try:
    with engine.connect() as connection:
        result = connection.execute(
            text("SELECT version()")
        )

        print("AMANAH DATABASE CONNECTED!")
        print(result.scalar())

except Exception as error:
    print("DATABASE CONNECTION FAILED")
    print(error)