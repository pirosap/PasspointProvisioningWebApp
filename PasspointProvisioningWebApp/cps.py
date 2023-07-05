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
windows_script_path = '/path/to/helper/generate_profile.pl'
android_script_path = '/path/to/helper/generate_profile_android.pl'
ios_script_path = '/path/to/helper/generate_profile_ios.pl'

@app.route('/generate_profile', methods=['POST'])
def generate_profile():
    data = request.get_json()
    ukey = data['ukey']
    client_type = data['client_type']
    username = session.get('username', '')
    password = session.get('password', '')

    # クライアントの種別に応じた処理を実行
    if client_type == 'Windows':
        # Windows用の処理
        cmd = ['perl', windows_script_path, username, password]
        file_extension = 'xml'
    elif client_type == 'Android':
        # Android用の処理
        cmd = ['perl', android_script_path, username, password]
        file_extension = 'config'
    elif client_type == 'iOS/macOS':
        # iOS/macOS用の処理
        cmd = ['perl', ios_script_path, username, password]
        file_extension = 'mobileconfig'
    else:
        # クライアントの種別が不正な場合の処理
        return jsonify(error='Invalid client type'), 400

    result = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)

    # 実行結果を受け取る
    output = result.stdout

    # ランダムな一意の文字列をファイル名に組み込む
    session_id = str(uuid.uuid4())
    #filename = f'passpoint_{session_id}.xml'
    filename = f'passpoint_{session_id}.{file_extension}'

    # XMLデータをRedisに保存
    redis_client.set(filename, output)

    # Redisに保存されたデータの有効期限を設定
    redis_client.expire(filename, 60)  # TTLを指定

    # レスポンスデータを作成
    response_data = {'filename': filename}

    return jsonify(response_data)

@app.route('/get_profile/<filename>', methods=['GET'])
def get_profile(filename):
    file_extension = os.path.splitext(filename)[1]

    if file_extension == '.xml':
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
    elif file_extension == '.config':
        # Redisから指定されたファイル名のデータを取得
        data = redis_client.get(filename)

        if data is not None:
            # ファイル名の拡張子が.configの場合はapplication/x-wifi-configとしてレスポンスを返す
            response = send_file(
                io.BytesIO(data),
                mimetype='application/x-wifi-config',
                as_attachment=True,
                download_name=filename
            )
            return response
        else:
            # データが存在しない場合はエラーを返す
            return jsonify({'error': 'File not found'}), 404
    elif file_extension == '.mobileconfig':
        # Redisから指定されたファイル名のデータを取得
        data = redis_client.get(filename)

        if data is not None:
            # ファイル名の拡張子が.mobileconfigの場合はapplication/x-apple-aspen-configとしてレスポンスを返す
            response = send_file(
                io.BytesIO(data),
                mimetype='application/x-apple-aspen-config',
                as_attachment=True,
                download_name=filename
            )
            return response
        else:
            # データが存在しない場合はエラーを返す
            return jsonify({'error': 'File not found'}), 404
    else:
        # サポートされていないファイル拡張子の場合はエラーを返す
        return jsonify({'error': 'Unsupported file extension'}), 400

@app.route('/', methods=['GET', 'POST'])
def login():
    if 'username' in session:
        return redirect(url_for('home'))

    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']

        # ユーザー名とNT-Passwordを照合するためにデータベースから検索します
        cur = mysql.connection.cursor()
        query = "SELECT * FROM radcheck WHERE username = %s AND attribute = 'NT-Password'"
        cur.execute(query, (username,))
        user = cur.fetchone()

        if user:
            db_password = user[4]
            if nt_password_hash(password) == bytes.fromhex(db_password):
                # 認証成功した場合、セッションにユーザー名を保存します
                session['username'] = username
                session['password'] = password
                # クライアントの種別を判定してセッションに保存します
                user_agent = request.headers.get('User-Agent', '')
                if 'Windows' in user_agent:
                    session['client_type'] = 'Windows'
                elif 'iPhone' in user_agent or 'iPad' in user_agent or 'Mac' in user_agent:
                    session['client_type'] = 'iOS/macOS'
                elif 'Android' in user_agent:
                    session['client_type'] = 'Android'
                else:
                    session['client_type'] = 'Unknown'

                session['authenticated'] = True
                cur.close()
                return redirect(url_for('home'))
            else:
                # パスワードが誤っている場合のエラーメッセージを表示します
                error = 'ユーザー名が見つからないか、パスワードが誤っています。'
                conn.close()
                return render_template('login.html', error=error)
        else:
            # ユーザーが見つからない場合のエラーメッセージを表示します
            error = 'ユーザー名が見つからないか、パスワードが誤っています。'
            conn.close()
            return render_template('login.html', error=error)

    return render_template('login.html')

@app.route('/home')
def home():
    if session.get('authenticated'):
        username = session.get('username', '')
        password = session.get('password', '')

        if redis_client.exists(username):
            ukey = redis_client.get(username).decode('utf-8')
        else:
            # キーが存在しない場合の処理
            ukey = generate_key(20)
            redis_client.set(username, ukey, nx=True, ex=60)

        # クライアントの種別をセッションから取得します
        client_type = session.get('client_type')

        # レンダリングするテンプレートにクライアントの種別を渡します
        return render_template('home.html', username=username, password=password, ukey=ukey, client_type=client_type)

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

