# Python side of the repository: controller port, parity tests, MuJoCo model checks.
#   docker build -t tumbling-target-capture .
#   docker run --rm tumbling-target-capture                                   # runs the test suite
#   docker run --rm -v "$PWD/out:/out" tumbling-target-capture python python/gnc/demo.py /out/demo.png
FROM python:3.10-slim

WORKDIR /repo
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

CMD ["pytest", "-v"]
