import hashlib
import random
import string

def generate_key(length):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def nt_password_hash(password):
    return hashlib.new('md4', password.encode('utf-16le')).digest()
