FROM python:3
RUN pip install waitress
RUN pip install flask
RUN pip install pdf2image
RUN apt-get update
RUN apt-get install poppler-utils -y
WORKDIR /app
EXPOSE 5000
