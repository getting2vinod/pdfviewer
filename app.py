from flask import Flask, render_template, request, redirect, url_for
import os
from waitress import serve
from pdf2image import convert_from_path
from authapi import check_login, init, auth, username
import logging

route_prefix = os.getenv('APP_ROUTE') or ""

if(route_prefix != ""):
    route_prefix = "/" + route_prefix

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'static/pdfs'
app.config['JPG_FOLDER'] = 'static/jpegs'
app.register_blueprint(auth)

init(app)

def pdf_to_jpeg(pdf_path, output_folder):
    # Convert PDF pages to images
    images = convert_from_path(pdf_path)

    # Create the output folder if it doesn't exist
    os.makedirs(output_folder, exist_ok=True)

    # Save each image as a JPEG file
    for i, image in enumerate(images):
        image.save(os.path.join(output_folder,os.path.basename(pdf_path) + f'_page_{i + 1}.jpg'), 'JPEG')
    
   
def last_5chars(x):
    return(x[-5:])   


@app.route('/')
def index():
    pdf_files = os.listdir(app.config['UPLOAD_FOLDER'])
    return render_template('index.html', pdf_files=pdf_files,route=route_prefix,username=username())


@app.route('/viewer')
def viewer():
    pdf = request.args.get('pdf')
    if '.pdf' in pdf.lower():
        ispdf = True
        all_files = os.listdir(app.config['JPG_FOLDER'])
        img_files = []
        for filename in sorted(all_files, key = last_5chars):
            print (filename)
            if pdf in filename:
                img_files.append(filename)
        print (img_files)
    else:
        #should be a direct file
        ispdf = False
        img_files = []
        img_files.append(os.path.join(app.config['UPLOAD_FOLDER'], pdf))
    
    return render_template('viewer.html', img_files=img_files, pdf=pdf, ispdf=ispdf,route=route_prefix)
    

@app.route('/upload', methods=['POST'])
def upload():
    if 'pdf' not in request.files:
        return redirect(request.url)

    pdf_file = request.files['pdf']

    if pdf_file.filename == '':
        return redirect(request.url)

    if pdf_file:
        pdf_path = os.path.join(app.config['UPLOAD_FOLDER'], pdf_file.filename)
        pdf_file.save(pdf_path)
        if pdf_file.content_type == "application/pdf":
            pdf_to_jpeg(pdf_path=pdf_path, output_folder=app.config['JPG_FOLDER'])
        return redirect(route_prefix + url_for('index'))

@app.route('/delete/<pdf>', methods=['POST'])
def delete(pdf):
    all_files = os.listdir(app.config['JPG_FOLDER'])
    img_files = []
    for filename in sorted(all_files, key = last_5chars):
        print (filename)
        if pdf in filename:
            if os.path.exists(filename):
                os.remove(filename)
    
    if os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], pdf)):
        os.remove(os.path.join(app.config['UPLOAD_FOLDER'], pdf))
    
    return redirect(route_prefix + url_for('index'))


if __name__ == '__main__':
    serve(app, host='0.0.0.0', port=4000)
    #app.run(debug=True)