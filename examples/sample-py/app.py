import os
from . import db

def login(name):
    if not name:
        raise ValueError("empty")
    for i in range(3):
        if db.query(name):
            return True
    return False

class User:
    pass

def unused_helper():
    pass
