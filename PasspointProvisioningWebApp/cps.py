from flask import Flask, render_template, request, redirect, url_for, session, make_response, send_file, flash
from flask_mysqldb import MySQL
from flask import jsonify
import hashlib
import random
import string
import redis
import subprocess
import urllib.parse
import os
import uuid
import sys
import io

app = Flask(__name__)
app.secret_key = 'your-secret-key'

# Redisクライアントを初期化します
redis_host = 'localhost'
redis_port = 6379
redis_db = 0
redis_client = redis.Redis(host=redis_host, port=redis_port, db=redis_db)

# MySQLの接続情報を設定します
config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '/path/to/helper/config.py')
sys.path.append(os.path.dirname(config_path))
from config import MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB

utils_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '/path/to/helper/utils.py')
sys.path.append(os.path.dirname(utils_path))
from utils import generate_key, nt_password_hash

app.config['MYSQL_HOST'] = MYSQL_HOST
app.config['MYSQL_USER'] = MYSQL_USER
app.config['MYSQL_PASSWORD'] = MYSQL_PASSWORD
app.config['MYSQL_DB'] = MYSQL_DB

mysql = MySQL(app)

script_path = '/path/to/helper/generate_profile.pl'

@app.route('/generate_profile', methods=['POST'])
def generate_profile():
    data = request.get_json()
    ukey = data['ukey']
    username = session.get('username', '')
    password = session.get('password', '')

    # ukey, username, passwordを引数として外部のPerlスクリプトを実行
    cmd = ['perl', script_path, username, password]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)

    # 実行結果を受け取る
    output = result.stdout

    # ランダムな一意の文字列をファイル名に組み込む
    session_id = str(uuid.uuid4())
    filename = f'passpoint_{session_id}.xml'

    # XMLデータをRedisに保存
    redis_client.set(filename, output)

    # Redisに保存されたデータの有効期限を設定
    redis_client.expire(filename, 60)  # TTLを指定

    # レスポンスデータを作成
    response_data = {'filename': filename}

    return jsonify(response_data)

@app.route('/get_profile/<filename>', methods=['GET'])
def get_profile(filename):
    if not session.get('authenticated'):
        error = 'ログインされていません'
        return render_template('login.html', error=error)
    # Redisから指定されたファイル名のデータを取得
    data = redis_client.get(filename)

    if data is not None:
        # データが存在する場合はXMLファイルとしてレスポンスを返す
        response = send_file(
            io.BytesIO(data),
            mimetype='application/xml',
            as_attachment=True,
            download_name=filename
        )
        return response
    else:
        # データが存在しない場合はエラーを返す
        return jsonify({'error': 'File not found'}), 404

@app.route('/', methods=['GET', 'POST'])
def login():
    if 'username' in session:
        return redirect(url_for('home'))

    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']

        # ユーザー名とNT-Passwordを照合するためにデータベースから検索します
        cur = mysql.connection.cursor()
        cur.execute("SELECT * FROM radcheck WHERE username = %s AND attribute = 'NT-Password'", (username,))
        user = cur.fetchone()

        if user:
            db_password = user[4]
            if nt_password_hash(password) == bytes.fromhex(db_password):
                # 認証成功した場合、セッションにユーザー名を保存します
                session['username'] = username
                session['password'] = password
                session['authenticated'] = True
                return redirect(url_for('home'))
            else:
                # パスワードが誤っている場合のエラーメッセージを表示します
                error = 'ユーザー名が見つからないか、パスワードが誤っています。'
                return render_template('login.html', error=error)
        else:
            # ユーザーが見つからない場合のエラーメッセージを表示します
            error = 'ユーザー名が見つからないか、パスワードが誤っています。'
            return render_template('login.html', error=error)

    return render_template('login.html')

@app.route('/home')
def home():
    if 'username' in session:
        username = session.get('username', '')
        password = session.get('password', '')

        # ユーザーが認証された場合にのみ実行
        if session.get('authenticated'):
            # キーが存在しない場合のみ実行
            if not redis_client.exists(username):
                # ランダムなキーを生成
                ukey = generate_key(20)

                # RedisにキーとユーザーIDをセット（NXオプションとTTLを指定）
                redis_client.set(username, ukey, nx=True, ex=60)

            # キーをテンプレートに渡す
            ukey = redis_client.get(username).decode('utf-8')
        else:
            ukey = None

        return render_template('home.html', username=username, password=password, ukey=ukey)

    # 認証されていないユーザーはログイン画面にリダイレクトします
    return redirect(url_for('login'))

@app.route('/logout')
def logout():
    if 'username' in session:
        # セッションからユーザー名を削除します
        session.pop('username', None)

        # キャッシュを無効化するためにレスポンスヘッダーを設定します
        response = make_response(redirect(url_for('login')))
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        return response

    return redirect(url_for('login'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=443, ssl_context=('/path/to/helper/cert.pem', '/path/to/helper/privkey.pem'))

