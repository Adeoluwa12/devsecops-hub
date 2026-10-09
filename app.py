from flask import Flask, jsonify, request
import sqlite3
import os

app = Flask(__name__)

@app.route("/")
def index():
    return jsonify(service="devsecops-hub", status="ok")

@app.route("/health")
def health():
    return jsonify(status="healthy app running on port 8080"), 200

@app.route("/users")
def users():
    # SAST flaw: SQL query built from unsanitised user input (SQL injection)
    username = request.args.get("name", "")
    conn = sqlite3.connect("users.db")
    cur = conn.cursor()
    cur.execute(f"SELECT * FROM users WHERE username = '{username}'")
    rows = cur.fetchall()
    conn.close()
    return jsonify(results=rows)

@app.route("/calc")
def calc():
    # SAST flaw: arbitrary code execution via eval() on user input
    expr = request.args.get("expr", "0")
    result = eval(expr)
    return jsonify(result=result)

if __name__ == "__main__":
    # SAST flaw: debug mode enabled in production
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True)