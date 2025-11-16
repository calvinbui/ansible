FROM public.ecr.aws/docker/library/python:3.14.0
LABEL skip.prune=true
WORKDIR /tmp

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    rsync \
    libssh-dev \
  && rm -rf /var/lib/apt/lists/*

RUN pip3 install -U pip

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY requirements.yml .
RUN ansible-galaxy install -r requirements.yml
