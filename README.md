# PasspointProvisioningTools
Tools and example codes for Passpoint profile provisioning, mainly for OpenRoaming.

## Features
- The tools and codes help operators develop their own Passpoint profile provisioning systems.
- The CGI scripts allow end users to download Passpoint profile and configure Wi-Fi without typing in Wi-Fi ID/password or certificate.

## Directory layout
- user: Website with user's login, i.e., with access control.
- ext: Open website where Windows Wi-Fi Settings can download the profile from.
- etc: Storage for configuration and certificate files.

# PasspointProvisioningWebApp
@hgot07 さんが開発・公開されているPasspointProvisioningTools を元に、FreeRADIUSのバックエンドにMariaDB(mysql）を使用している構成で動作するWebアプリケーションにしたものです。

## 想定している構成
- IdP側 FreeRADIUS Version 3.2.2 / MariaDB 10.5.16 / 
- 本アプリ側 Redis 6.2.7 / Python 3.9.16 / (Dev server) Flask 2.3.2
- クライアントは、Windows11 22H2以降であること

## 試し方
MariaDB上のradiusデータベース内のradcheckテーブルに保存されているusername/passwordの組み合わせでログインして、Cityroam用のPasspointプロファイルを発行することができます。  
radcheckテーブル上の値は、PEAP/MSCHAPv2やTTLS/MSCHAPv2用になっている環境を想定しています。

## 構成
PasspointProvisioningWebApp/cps.py
- Webアプリケーション本体

PasspointProvisioningWebApp/template/login.html 
- ログイン画面のテンプレート

PasspointProvisioningWebApp/template/home.html 
- ホーム画面のテンプレート

helper/generate_profile.pl
- PasspointProvisioningTools におけるpasspoint-win.config

helper/generate_profile_ios.pl
- PasspointProvisioningTools におけるpasspoint.mobileconfig

helper/pp-common.cfg
- プロファイル内部の値の初期値

helper/config.py
- データベース接続用設定

helper/utils.py
- NT Hash用関数など

helper/証明書関係一式

## 起動方法
Flaskの開発用サーバモードで起動  
```python3 cps.py```

本番系の環境で使用する場合は、WSGIを使用してください。  
Nginx + Gunicornの例  
- Ngnix 
```
location / {
                allow all;
                proxy_pass http://127.0.0.1:8000;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

```
- Gunicorn
```
$ gunicorn cps:app --bind 127.0.0.1:8000 --daemon
```

