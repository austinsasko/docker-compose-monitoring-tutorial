from flask import Flask, render_template, request # type: ignore
import mysql.connector # type: ignore
import os


def connect():
    db_host="mariadb"
    db_port=3306
    if os.getenv("STAGING"):
        db_host = "mariadb_staging"
        db_port=os.getenv("DB_PORT")
    mydb = mysql.connector.connect(
    host=db_host,
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASS"),
    database=os.getenv("DB_NAME"),
    port=db_port
    )
    return mydb

def run_query(db, query, params=None):
    mycursor = db.cursor()
    mycursor.execute(query, params)
    results = mycursor.fetchall()
    result_list = []
    for result in results:
         result_list.append(result)
    mycursor.close()
    return result_list

app = Flask(__name__)

@app.route("/")
def main():
    content = ["1/24/2022", "Column 1", "Column 2", "Discord ID"]
    return render_template('index.html', content=content, title="Example web frontend")

if __name__ == "__main__":
    from waitress import serve # type: ignore
    print("Starting web server")
    web_port=5000
    if os.getenv('STAGING'):
        web_port=5001
    serve(app, host="0.0.0.0", port=web_port, url_scheme="https")

