from fastapi import FastAPI, APIRouter, HTTPException, Depends, UploadFile, File, Query
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import os
import logging
from pathlib import Path
from pydantic import BaseModel, Field, EmailStr
from typing import List, Optional
import uuid
from datetime import datetime, timedelta
from passlib.context import CryptContext
from jose import JWTError, jwt
import base64

ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')

# MongoDB connection
mongo_url = os.environ['MONGO_URL']
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ.get('DB_NAME', 'flames_up')]

# Create the main app
app = FastAPI(title="Flames-Up API")

# Create a router with the /api prefix
api_router = APIRouter(prefix="/api")

# Security
SECRET_KEY = os.environ.get("SECRET_KEY", "flames-up-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer()

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# ===================== MODELS =====================

class UserCreate(BaseModel):
    email: EmailStr
    password: str
    username: str
    full_name: str

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class UserUpdate(BaseModel):
    username: Optional[str] = None
    full_name: Optional[str] = None
    bio: Optional[str] = None
    profile_image: Optional[str] = None
    location: Optional[str] = None

class User(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    email: str
    username: str
    full_name: str
    bio: str = ""
    profile_image: str = ""
    location: str = ""
    followers_count: int = 0
    following_count: int = 0
    posts_count: int = 0
    is_verified: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)

class PostCreate(BaseModel):
    content: str
    image: Optional[str] = None  # Base64 image
    location: Optional[str] = None

class PostUpdate(BaseModel):
    content: Optional[str] = None

class Post(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    user_username: str
    user_full_name: str
    user_profile_image: str = ""
    content: str
    image: Optional[str] = None
    location: Optional[str] = None
    likes_count: int = 0
    comments_count: int = 0
    liked_by: List[str] = []
    created_at: datetime = Field(default_factory=datetime.utcnow)

class CommentCreate(BaseModel):
    content: str

class Comment(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    post_id: str
    user_id: str
    user_username: str
    user_full_name: str
    user_profile_image: str = ""
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)

class StatusCreate(BaseModel):
    content: str
    image: Optional[str] = None  # Base64 image
    background_color: str = "#6366f1"

class Status(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    user_username: str
    user_full_name: str
    user_profile_image: str = ""
    content: str
    image: Optional[str] = None
    background_color: str = "#6366f1"
    viewers: List[str] = []
    created_at: datetime = Field(default_factory=datetime.utcnow)
    expires_at: datetime = Field(default_factory=lambda: datetime.utcnow() + timedelta(hours=24))

class MessageCreate(BaseModel):
    receiver_id: str
    content: str
    image: Optional[str] = None

class Message(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    sender_id: str
    receiver_id: str
    content: str
    image: Optional[str] = None
    is_read: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)

class Conversation(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    participants: List[str]
    last_message: str = ""
    last_message_time: datetime = Field(default_factory=datetime.utcnow)
    unread_count: dict = {}

class NotificationCreate(BaseModel):
    user_id: str
    type: str  # like, comment, follow, message
    title: str
    body: str
    data: dict = {}

class Notification(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    type: str
    title: str
    body: str
    data: dict = {}
    is_read: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)

class PlaceCreate(BaseModel):
    name: str
    description: str
    address: str
    latitude: float
    longitude: float
    category: str
    image: Optional[str] = None
    rating: float = 0.0

class Place(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    description: str
    address: str
    latitude: float
    longitude: float
    category: str
    image: Optional[str] = None
    rating: float = 0.0
    reviews_count: int = 0
    created_by: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)

class Follow(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    follower_id: str
    following_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)

# ===================== HELPER FUNCTIONS =====================

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    try:
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        user = await db.users.find_one({"id": user_id})
        if user is None:
            raise HTTPException(status_code=401, detail="User not found")
        return user
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

async def create_notification(user_id: str, type: str, title: str, body: str, data: dict = {}):
    notification = Notification(
        user_id=user_id,
        type=type,
        title=title,
        body=body,
        data=data
    )
    await db.notifications.insert_one(notification.dict())

# ===================== AUTH ENDPOINTS =====================

@api_router.post("/auth/register")
async def register(user_data: UserCreate):
    # Check if email exists
    existing = await db.users.find_one({"email": user_data.email})
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    # Check if username exists
    existing_username = await db.users.find_one({"username": user_data.username})
    if existing_username:
        raise HTTPException(status_code=400, detail="Username already taken")
    
    # Create user
    hashed_password = get_password_hash(user_data.password)
    user = User(
        email=user_data.email,
        username=user_data.username,
        full_name=user_data.full_name
    )
    user_dict = user.dict()
    user_dict["password_hash"] = hashed_password
    
    await db.users.insert_one(user_dict)
    
    token = create_access_token({"sub": user.id})
    return {"token": token, "user": user.dict()}

@api_router.post("/auth/login")
async def login(user_data: UserLogin):
    user = await db.users.find_one({"email": user_data.email})
    if not user or not verify_password(user_data.password, user.get("password_hash", "")):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    
    token = create_access_token({"sub": user["id"]})
    user_response = {k: v for k, v in user.items() if k != "password_hash" and k != "_id"}
    return {"token": token, "user": user_response}

@api_router.get("/auth/me")
async def get_me(current_user: dict = Depends(get_current_user)):
    user_response = {k: v for k, v in current_user.items() if k != "password_hash" and k != "_id"}
    return user_response

# ===================== USER ENDPOINTS =====================

@api_router.put("/users/me")
async def update_profile(update_data: UserUpdate, current_user: dict = Depends(get_current_user)):
    update_dict = {k: v for k, v in update_data.dict().items() if v is not None}
    if update_dict:
        await db.users.update_one({"id": current_user["id"]}, {"$set": update_dict})
        # Update user info in posts
        await db.posts.update_many(
            {"user_id": current_user["id"]},
            {"$set": {
                "user_username": update_dict.get("username", current_user["username"]),
                "user_full_name": update_dict.get("full_name", current_user["full_name"]),
                "user_profile_image": update_dict.get("profile_image", current_user.get("profile_image", ""))
            }}
        )
    updated_user = await db.users.find_one({"id": current_user["id"]})
    return {k: v for k, v in updated_user.items() if k != "password_hash" and k != "_id"}

@api_router.get("/users/{user_id}")
async def get_user(user_id: str, current_user: dict = Depends(get_current_user)):
    user = await db.users.find_one({"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    is_following = await db.follows.find_one({
        "follower_id": current_user["id"],
        "following_id": user_id
    }) is not None
    
    user_response = {k: v for k, v in user.items() if k != "password_hash" and k != "_id"}
    user_response["is_following"] = is_following
    return user_response

@api_router.get("/users/search/{query}")
async def search_users(query: str, current_user: dict = Depends(get_current_user)):
    users = await db.users.find({
        "$or": [
            {"username": {"$regex": query, "$options": "i"}},
            {"full_name": {"$regex": query, "$options": "i"}}
        ]
    }).limit(20).to_list(20)
    return [{k: v for k, v in u.items() if k != "password_hash" and k != "_id"} for u in users]

@api_router.post("/users/{user_id}/follow")
async def follow_user(user_id: str, current_user: dict = Depends(get_current_user)):
    if user_id == current_user["id"]:
        raise HTTPException(status_code=400, detail="Cannot follow yourself")
    
    target_user = await db.users.find_one({"id": user_id})
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")
    
    existing = await db.follows.find_one({
        "follower_id": current_user["id"],
        "following_id": user_id
    })
    
    if existing:
        # Unfollow
        await db.follows.delete_one({"id": existing["id"]})
        await db.users.update_one({"id": current_user["id"]}, {"$inc": {"following_count": -1}})
        await db.users.update_one({"id": user_id}, {"$inc": {"followers_count": -1}})
        return {"following": False}
    else:
        # Follow
        follow = Follow(follower_id=current_user["id"], following_id=user_id)
        await db.follows.insert_one(follow.dict())
        await db.users.update_one({"id": current_user["id"]}, {"$inc": {"following_count": 1}})
        await db.users.update_one({"id": user_id}, {"$inc": {"followers_count": 1}})
        
        # Create notification
        await create_notification(
            user_id=user_id,
            type="follow",
            title="New Follower",
            body=f"{current_user['username']} started following you",
            data={"follower_id": current_user["id"]}
        )
        return {"following": True}

# ===================== POST ENDPOINTS =====================

@api_router.post("/posts")
async def create_post(post_data: PostCreate, current_user: dict = Depends(get_current_user)):
    post = Post(
        user_id=current_user["id"],
        user_username=current_user["username"],
        user_full_name=current_user["full_name"],
        user_profile_image=current_user.get("profile_image", ""),
        content=post_data.content,
        image=post_data.image,
        location=post_data.location
    )
    await db.posts.insert_one(post.dict())
    await db.users.update_one({"id": current_user["id"]}, {"$inc": {"posts_count": 1}})
    return post.dict()

@api_router.get("/posts")
async def get_posts(skip: int = 0, limit: int = 20, current_user: dict = Depends(get_current_user)):
    posts = await db.posts.find().sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    return [{k: v for k, v in p.items() if k != "_id"} for p in posts]

@api_router.get("/posts/feed")
async def get_feed(skip: int = 0, limit: int = 20, current_user: dict = Depends(get_current_user)):
    # Get posts from followed users + own posts
    following = await db.follows.find({"follower_id": current_user["id"]}).to_list(1000)
    following_ids = [f["following_id"] for f in following]
    following_ids.append(current_user["id"])
    
    posts = await db.posts.find({"user_id": {"$in": following_ids}}).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    
    if len(posts) < limit:
        # Get more posts from others
        other_posts = await db.posts.find({"user_id": {"$nin": following_ids}}).sort("created_at", -1).limit(limit - len(posts)).to_list(limit - len(posts))
        posts.extend(other_posts)
    
    return [{k: v for k, v in p.items() if k != "_id"} for p in posts]

@api_router.get("/posts/{post_id}")
async def get_post(post_id: str, current_user: dict = Depends(get_current_user)):
    post = await db.posts.find_one({"id": post_id})
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    return {k: v for k, v in post.items() if k != "_id"}

@api_router.post("/posts/{post_id}/like")
async def like_post(post_id: str, current_user: dict = Depends(get_current_user)):
    post = await db.posts.find_one({"id": post_id})
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    
    liked_by = post.get("liked_by", [])
    if current_user["id"] in liked_by:
        # Unlike
        liked_by.remove(current_user["id"])
        await db.posts.update_one({"id": post_id}, {"$set": {"liked_by": liked_by}, "$inc": {"likes_count": -1}})
        return {"liked": False, "likes_count": post["likes_count"] - 1}
    else:
        # Like
        liked_by.append(current_user["id"])
        await db.posts.update_one({"id": post_id}, {"$set": {"liked_by": liked_by}, "$inc": {"likes_count": 1}})
        
        if post["user_id"] != current_user["id"]:
            await create_notification(
                user_id=post["user_id"],
                type="like",
                title="New Like",
                body=f"{current_user['username']} liked your post",
                data={"post_id": post_id}
            )
        return {"liked": True, "likes_count": post["likes_count"] + 1}

@api_router.delete("/posts/{post_id}")
async def delete_post(post_id: str, current_user: dict = Depends(get_current_user)):
    post = await db.posts.find_one({"id": post_id})
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    if post["user_id"] != current_user["id"]:
        raise HTTPException(status_code=403, detail="Not authorized")
    
    await db.posts.delete_one({"id": post_id})
    await db.comments.delete_many({"post_id": post_id})
    await db.users.update_one({"id": current_user["id"]}, {"$inc": {"posts_count": -1}})
    return {"deleted": True}

@api_router.get("/users/{user_id}/posts")
async def get_user_posts(user_id: str, skip: int = 0, limit: int = 20, current_user: dict = Depends(get_current_user)):
    posts = await db.posts.find({"user_id": user_id}).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    return [{k: v for k, v in p.items() if k != "_id"} for p in posts]

# ===================== COMMENT ENDPOINTS =====================

@api_router.post("/posts/{post_id}/comments")
async def create_comment(post_id: str, comment_data: CommentCreate, current_user: dict = Depends(get_current_user)):
    post = await db.posts.find_one({"id": post_id})
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    
    comment = Comment(
        post_id=post_id,
        user_id=current_user["id"],
        user_username=current_user["username"],
        user_full_name=current_user["full_name"],
        user_profile_image=current_user.get("profile_image", ""),
        content=comment_data.content
    )
    await db.comments.insert_one(comment.dict())
    await db.posts.update_one({"id": post_id}, {"$inc": {"comments_count": 1}})
    
    if post["user_id"] != current_user["id"]:
        await create_notification(
            user_id=post["user_id"],
            type="comment",
            title="New Comment",
            body=f"{current_user['username']} commented on your post",
            data={"post_id": post_id}
        )
    
    return comment.dict()

@api_router.get("/posts/{post_id}/comments")
async def get_comments(post_id: str, skip: int = 0, limit: int = 50, current_user: dict = Depends(get_current_user)):
    comments = await db.comments.find({"post_id": post_id}).sort("created_at", 1).skip(skip).limit(limit).to_list(limit)
    return [{k: v for k, v in c.items() if k != "_id"} for c in comments]

# ===================== STATUS ENDPOINTS =====================

@api_router.post("/statuses")
async def create_status(status_data: StatusCreate, current_user: dict = Depends(get_current_user)):
    status = Status(
        user_id=current_user["id"],
        user_username=current_user["username"],
        user_full_name=current_user["full_name"],
        user_profile_image=current_user.get("profile_image", ""),
        content=status_data.content,
        image=status_data.image,
        background_color=status_data.background_color
    )
    await db.statuses.insert_one(status.dict())
    return status.dict()

@api_router.get("/statuses")
async def get_statuses(current_user: dict = Depends(get_current_user)):
    # Get statuses from last 24 hours
    cutoff = datetime.utcnow() - timedelta(hours=24)
    statuses = await db.statuses.find({"created_at": {"$gte": cutoff}}).sort("created_at", -1).to_list(100)
    
    # Group by user
    user_statuses = {}
    for s in statuses:
        uid = s["user_id"]
        if uid not in user_statuses:
            user_statuses[uid] = {
                "user_id": uid,
                "user_username": s["user_username"],
                "user_full_name": s["user_full_name"],
                "user_profile_image": s.get("user_profile_image", ""),
                "statuses": [],
                "has_unviewed": False
            }
        status_dict = {k: v for k, v in s.items() if k != "_id"}
        if current_user["id"] not in s.get("viewers", []):
            user_statuses[uid]["has_unviewed"] = True
        user_statuses[uid]["statuses"].append(status_dict)
    
    # Put current user's statuses first
    result = []
    if current_user["id"] in user_statuses:
        result.append(user_statuses.pop(current_user["id"]))
    result.extend(list(user_statuses.values()))
    
    return result

@api_router.post("/statuses/{status_id}/view")
async def view_status(status_id: str, current_user: dict = Depends(get_current_user)):
    status = await db.statuses.find_one({"id": status_id})
    if not status:
        raise HTTPException(status_code=404, detail="Status not found")
    
    viewers = status.get("viewers", [])
    if current_user["id"] not in viewers:
        viewers.append(current_user["id"])
        await db.statuses.update_one({"id": status_id}, {"$set": {"viewers": viewers}})
    
    return {"viewed": True}

# ===================== MESSAGE ENDPOINTS =====================

@api_router.get("/conversations")
async def get_conversations(current_user: dict = Depends(get_current_user)):
    conversations = await db.conversations.find({
        "participants": current_user["id"]
    }).sort("last_message_time", -1).to_list(50)
    
    result = []
    for conv in conversations:
        other_id = [p for p in conv["participants"] if p != current_user["id"]][0]
        other_user = await db.users.find_one({"id": other_id})
        if other_user:
            conv_data = {k: v for k, v in conv.items() if k != "_id"}
            conv_data["other_user"] = {
                "id": other_user["id"],
                "username": other_user["username"],
                "full_name": other_user["full_name"],
                "profile_image": other_user.get("profile_image", "")
            }
            conv_data["unread_count"] = conv.get("unread_count", {}).get(current_user["id"], 0)
            result.append(conv_data)
    
    return result

@api_router.post("/messages")
async def send_message(message_data: MessageCreate, current_user: dict = Depends(get_current_user)):
    receiver = await db.users.find_one({"id": message_data.receiver_id})
    if not receiver:
        raise HTTPException(status_code=404, detail="Receiver not found")
    
    # Create message
    message = Message(
        sender_id=current_user["id"],
        receiver_id=message_data.receiver_id,
        content=message_data.content,
        image=message_data.image
    )
    await db.messages.insert_one(message.dict())
    
    # Update or create conversation
    participants = sorted([current_user["id"], message_data.receiver_id])
    conversation = await db.conversations.find_one({"participants": participants})
    
    if conversation:
        unread = conversation.get("unread_count", {})
        unread[message_data.receiver_id] = unread.get(message_data.receiver_id, 0) + 1
        await db.conversations.update_one(
            {"id": conversation["id"]},
            {"$set": {
                "last_message": message_data.content[:100],
                "last_message_time": datetime.utcnow(),
                "unread_count": unread
            }}
        )
    else:
        conv = Conversation(
            participants=participants,
            last_message=message_data.content[:100],
            last_message_time=datetime.utcnow(),
            unread_count={message_data.receiver_id: 1}
        )
        await db.conversations.insert_one(conv.dict())
    
    # Create notification
    await create_notification(
        user_id=message_data.receiver_id,
        type="message",
        title="New Message",
        body=f"{current_user['username']}: {message_data.content[:50]}",
        data={"sender_id": current_user["id"]}
    )
    
    return message.dict()

@api_router.get("/messages/{user_id}")
async def get_messages(user_id: str, skip: int = 0, limit: int = 50, current_user: dict = Depends(get_current_user)):
    messages = await db.messages.find({
        "$or": [
            {"sender_id": current_user["id"], "receiver_id": user_id},
            {"sender_id": user_id, "receiver_id": current_user["id"]}
        ]
    }).sort("created_at", 1).skip(skip).limit(limit).to_list(limit)
    
    # Mark as read
    await db.messages.update_many(
        {"sender_id": user_id, "receiver_id": current_user["id"], "is_read": False},
        {"$set": {"is_read": True}}
    )
    
    # Update conversation unread count
    participants = sorted([current_user["id"], user_id])
    await db.conversations.update_one(
        {"participants": participants},
        {"$set": {f"unread_count.{current_user['id']}": 0}}
    )
    
    return [{k: v for k, v in m.items() if k != "_id"} for m in messages]

# ===================== NOTIFICATION ENDPOINTS =====================

@api_router.get("/notifications")
async def get_notifications(skip: int = 0, limit: int = 50, current_user: dict = Depends(get_current_user)):
    notifications = await db.notifications.find({"user_id": current_user["id"]}).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    return [{k: v for k, v in n.items() if k != "_id"} for n in notifications]

@api_router.get("/notifications/unread-count")
async def get_unread_count(current_user: dict = Depends(get_current_user)):
    count = await db.notifications.count_documents({"user_id": current_user["id"], "is_read": False})
    return {"count": count}

@api_router.post("/notifications/mark-read")
async def mark_notifications_read(current_user: dict = Depends(get_current_user)):
    await db.notifications.update_many(
        {"user_id": current_user["id"], "is_read": False},
        {"$set": {"is_read": True}}
    )
    return {"success": True}

@api_router.post("/notifications/{notification_id}/read")
async def mark_notification_read(notification_id: str, current_user: dict = Depends(get_current_user)):
    await db.notifications.update_one(
        {"id": notification_id, "user_id": current_user["id"]},
        {"$set": {"is_read": True}}
    )
    return {"success": True}

# ===================== PLACE ENDPOINTS =====================

@api_router.post("/places")
async def create_place(place_data: PlaceCreate, current_user: dict = Depends(get_current_user)):
    place = Place(
        name=place_data.name,
        description=place_data.description,
        address=place_data.address,
        latitude=place_data.latitude,
        longitude=place_data.longitude,
        category=place_data.category,
        image=place_data.image,
        rating=place_data.rating,
        created_by=current_user["id"]
    )
    await db.places.insert_one(place.dict())
    return place.dict()

@api_router.get("/places")
async def get_places(
    category: Optional[str] = None,
    skip: int = 0,
    limit: int = 20,
    current_user: dict = Depends(get_current_user)
):
    query = {}
    if category:
        query["category"] = category
    
    places = await db.places.find(query).sort("rating", -1).skip(skip).limit(limit).to_list(limit)
    return [{k: v for k, v in p.items() if k != "_id"} for p in places]

@api_router.get("/places/nearby")
async def get_nearby_places(
    latitude: float,
    longitude: float,
    radius: float = 10.0,  # km
    current_user: dict = Depends(get_current_user)
):
    # Simple distance calculation (not using geospatial indexes for simplicity)
    places = await db.places.find().to_list(100)
    
    def haversine(lat1, lon1, lat2, lon2):
        from math import radians, sin, cos, sqrt, atan2
        R = 6371  # Earth's radius in km
        lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * atan2(sqrt(a), sqrt(1-a))
        return R * c
    
    nearby = []
    for p in places:
        dist = haversine(latitude, longitude, p["latitude"], p["longitude"])
        if dist <= radius:
            place_dict = {k: v for k, v in p.items() if k != "_id"}
            place_dict["distance"] = round(dist, 2)
            nearby.append(place_dict)
    
    nearby.sort(key=lambda x: x["distance"])
    return nearby[:20]

@api_router.get("/places/{place_id}")
async def get_place(place_id: str, current_user: dict = Depends(get_current_user)):
    place = await db.places.find_one({"id": place_id})
    if not place:
        raise HTTPException(status_code=404, detail="Place not found")
    return {k: v for k, v in place.items() if k != "_id"}

# ===================== DISCOVER ENDPOINTS =====================

@api_router.get("/discover/trending")
async def get_trending(current_user: dict = Depends(get_current_user)):
    # Get posts with most likes in last 7 days
    cutoff = datetime.utcnow() - timedelta(days=7)
    posts = await db.posts.find({"created_at": {"$gte": cutoff}}).sort("likes_count", -1).limit(20).to_list(20)
    return [{k: v for k, v in p.items() if k != "_id"} for p in posts]

@api_router.get("/discover/search")
async def search(query: str, current_user: dict = Depends(get_current_user)):
    # Search posts
    posts = await db.posts.find({
        "content": {"$regex": query, "$options": "i"}
    }).sort("created_at", -1).limit(20).to_list(20)
    
    # Search users
    users = await db.users.find({
        "$or": [
            {"username": {"$regex": query, "$options": "i"}},
            {"full_name": {"$regex": query, "$options": "i"}}
        ]
    }).limit(10).to_list(10)
    
    # Search places
    places = await db.places.find({
        "$or": [
            {"name": {"$regex": query, "$options": "i"}},
            {"description": {"$regex": query, "$options": "i"}}
        ]
    }).limit(10).to_list(10)
    
    return {
        "posts": [{k: v for k, v in p.items() if k != "_id"} for p in posts],
        "users": [{k: v for k, v in u.items() if k not in ["password_hash", "_id"]} for u in users],
        "places": [{k: v for k, v in p.items() if k != "_id"} for p in places]
    }

@api_router.get("/discover/suggested-users")
async def get_suggested_users(current_user: dict = Depends(get_current_user)):
    # Get users not followed by current user
    following = await db.follows.find({"follower_id": current_user["id"]}).to_list(1000)
    following_ids = [f["following_id"] for f in following]
    following_ids.append(current_user["id"])
    
    users = await db.users.find({"id": {"$nin": following_ids}}).sort("followers_count", -1).limit(10).to_list(10)
    return [{k: v for k, v in u.items() if k not in ["password_hash", "_id"]} for u in users]

# ===================== HEALTH CHECK =====================

@api_router.get("/")
async def root():
    return {"message": "Flames-Up API", "version": "1.0.0"}

@api_router.get("/health")
async def health_check():
    return {"status": "healthy"}

# Include the router
app.include_router(api_router)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()
