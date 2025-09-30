# Custom Superset Docker image with MySQL drivers
FROM apache/superset:5.0.0

# Switch to root user to install packages
USER root

# Install PyMySQL and create MySQLdb compatibility
RUN pip install PyMySQL

# Create MySQLdb compatibility module
RUN echo "# MySQLdb compatibility module" > /app/.venv/lib/python3.10/site-packages/MySQLdb.py && \
    echo "import pymysql" >> /app/.venv/lib/python3.10/site-packages/MySQLdb.py && \
    echo "pymysql.install_as_MySQLdb()" >> /app/.venv/lib/python3.10/site-packages/MySQLdb.py && \
    echo "from pymysql import *" >> /app/.venv/lib/python3.10/site-packages/MySQLdb.py

# Create initialization script
RUN echo '#!/bin/bash' > /app/init-superset.sh && \
    echo 'echo "Starting Superset initialization..."' >> /app/init-superset.sh && \
    echo 'superset db upgrade' >> /app/init-superset.sh && \
    echo 'superset fab create-admin --username admin --firstname Superset --lastname Admin --email admin@superset.com --password admin' >> /app/init-superset.sh && \
    echo 'superset init' >> /app/init-superset.sh && \
    echo 'echo "Superset initialization completed!"' >> /app/init-superset.sh && \
    chmod +x /app/init-superset.sh

# Switch back to superset user
USER superset

# Set working directory
WORKDIR /app