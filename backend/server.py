from fastapi import FastAPI, APIRouter, HTTPException, Depends, UploadFile, File, Query, Form
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
import httpx

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
    image: Optional[str] = None  # Single image (backward compat)
    images: Optional[List[str]] = None  # Multiple images/videos
    media_types: Optional[List[str]] = None  # "image" or "video" per item
    location: Optional[str] = None
    post_type: str = "lifestyle"  # "lifestyle", "check_in", "question"
    place_id: Optional[str] = None  # Google place_id for check-ins
    place_name: Optional[str] = None  # Place name for check-ins
    place_lat: Optional[float] = None  # Place latitude
    place_lng: Optional[float] = None  # Place longitude

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
    images: List[str] = []
    media_types: List[str] = []
    location: Optional[str] = None
    post_type: str = "lifestyle"  # "lifestyle", "check_in", "question"
    place_id: Optional[str] = None
    place_name: Optional[str] = None
    place_lat: Optional[float] = None
    place_lng: Optional[float] = None
    is_verified_checkin: bool = False  # True when proximity was verified
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
    # Build images list from both old and new fields
    images_list = []
    media_types_list = []
    if post_data.images:
        images_list = post_data.images
        media_types_list = post_data.media_types or ["image"] * len(images_list)
    elif post_data.image:
        images_list = [post_data.image]
        media_types_list = ["image"]

    # For check-in posts, set location to place name
    location = post_data.location
    if post_data.post_type == "check_in" and post_data.place_name:
        location = post_data.place_name

    post = Post(
        user_id=current_user["id"],
        user_username=current_user["username"],
        user_full_name=current_user["full_name"],
        user_profile_image=current_user.get("profile_image", ""),
        content=post_data.content,
        image=images_list[0] if images_list else None,
        images=images_list,
        media_types=media_types_list,
        location=location,
        post_type=post_data.post_type,
        place_id=post_data.place_id,
        place_name=post_data.place_name,
        place_lat=post_data.place_lat,
        place_lng=post_data.place_lng,
        is_verified_checkin=post_data.post_type == "check_in" and post_data.place_id is not None,
    )
    await db.posts.insert_one(post.dict())
    await db.users.update_one({"id": current_user["id"]}, {"$inc": {"posts_count": 1}})
    return post.dict()

@api_router.get("/posts")
async def get_posts(skip: int = 0, limit: int = 20, current_user: dict = Depends(get_current_user)):
    posts = await db.posts.find().sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    return [{k: v for k, v in p.items() if k != "_id"} for p in posts]

@api_router.get("/posts/feed")
async def get_feed(
    skip: int = 0,
    limit: int = 20,
    location: Optional[str] = None,
    current_user: dict = Depends(get_current_user)
):
    query: dict = {}
    
    if location and location not in ("global", "Global"):
        # Filter by location (case-insensitive partial match)
        query["location"] = {"$regex": location, "$options": "i"}
    
    if not query:
        # Default feed: followed users + own + others
        following = await db.follows.find({"follower_id": current_user["id"]}).to_list(1000)
        following_ids = [f["following_id"] for f in following]
        following_ids.append(current_user["id"])
        
        posts = await db.posts.find({"user_id": {"$in": following_ids}}).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
        
        if len(posts) < limit:
            other_posts = await db.posts.find({"user_id": {"$nin": following_ids}}).sort("created_at", -1).limit(limit - len(posts)).to_list(limit - len(posts))
            posts.extend(other_posts)
    else:
        posts = await db.posts.find(query).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    
    return [{k: v for k, v in p.items() if k != "_id"} for p in posts]

@api_router.get("/posts/nearby-feed")
async def get_nearby_feed(
    lat: float = Query(40.7128),
    lng: float = Query(-74.006),
    radius: float = Query(5.0),  # km
    skip: int = 0,
    limit: int = 20,
    current_user: dict = Depends(get_current_user)
):
    """Feed prioritizing check-in posts near user location, then place-tagged, then trending"""
    from math import radians, sin, cos, sqrt, atan2
    
    all_posts = await db.posts.find().sort("created_at", -1).limit(200).to_list(200)
    
    nearby_checkins = []
    place_tagged = []
    regular = []
    
    for p in all_posts:
        post_dict = {k: v for k, v in p.items() if k != "_id"}
        
        if p.get("post_type") == "check_in" and p.get("place_lat") and p.get("place_lng"):
            # Calculate distance
            R = 6371  # km
            lat1, lon1, lat2, lon2 = map(radians, [lat, lng, p["place_lat"], p["place_lng"]])
            dlat = lat2 - lat1
            dlon = lon2 - lon1
            a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
            c = 2 * atan2(sqrt(a), sqrt(1-a))
            dist = R * c
            
            if dist <= radius:
                post_dict["distance_km"] = round(dist, 2)
                nearby_checkins.append(post_dict)
            else:
                place_tagged.append(post_dict)
        elif p.get("place_id") or p.get("location"):
            place_tagged.append(post_dict)
        else:
            regular.append(post_dict)
    
    # Sort nearby by distance
    nearby_checkins.sort(key=lambda x: x.get("distance_km", 999))
    
    # Combine: nearby check-ins first, then place-tagged, then regular
    combined = nearby_checkins + place_tagged + regular
    
    return combined[skip:skip + limit]

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

# ===================== PROXIMITY VERIFICATION =====================

class ProximityCheck(BaseModel):
    user_lat: float
    user_lng: float
    place_lat: float
    place_lng: float

@api_router.post("/places/verify-proximity")
async def verify_proximity(data: ProximityCheck, current_user: dict = Depends(get_current_user)):
    """Check if user is within 200 meters of a place"""
    from math import radians, sin, cos, sqrt, atan2
    R = 6371000  # Earth's radius in meters
    lat1, lon1, lat2, lon2 = map(radians, [data.user_lat, data.user_lng, data.place_lat, data.place_lng])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    distance = R * c
    
    return {
        "is_near": distance <= 200,
        "distance_meters": round(distance, 1),
        "max_distance": 200,
    }

# ===================== HEALTH CHECK =====================

@api_router.get("/")
async def root():
    return {"message": "Flames-Up API", "version": "1.0.0"}

@api_router.get("/health")
async def health_check():
    return {"status": "healthy"}

# Cloudflare configuration
CF_ACCOUNT_ID = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
CF_API_TOKEN = os.environ.get("CLOUDFLARE_API_TOKEN", "")
CF_ACCOUNT_HASH = os.environ.get("CLOUDFLARE_ACCOUNT_HASH", "")
CF_DELIVERY_URL = os.environ.get("CLOUDFLARE_IMAGE_DELIVERY_URL", "")
CF_IMAGES_URL = f"https://api.cloudflare.com/client/v4/accounts/{CF_ACCOUNT_ID}/images/v1"
CF_STREAM_URL = f"https://api.cloudflare.com/client/v4/accounts/{CF_ACCOUNT_ID}/stream"

# Google Maps configuration
GOOGLE_MAPS_API_KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")

def cf_delivery(image_id: str, variant: str = "public") -> str:
    """Build Cloudflare image delivery URL"""
    return f"{CF_DELIVERY_URL}/{image_id}/{variant}"

# ===================== CLOUDFLARE IMAGE PIPELINE =====================

@api_router.post("/upload/image")
async def upload_image(
    file: UploadFile = File(...),
    folder: str = Form("uploads"),
    current_user: dict = Depends(get_current_user)
):
    """Upload image to Cloudflare Images → returns delivery URL"""
    if not CF_ACCOUNT_ID or not CF_API_TOKEN:
        raise HTTPException(status_code=500, detail="Cloudflare not configured")

    content = await file.read()
    try:
        async with httpx.AsyncClient(timeout=30.0) as client_http:
            response = await client_http.post(
                CF_IMAGES_URL,
                headers={"Authorization": f"Bearer {CF_API_TOKEN}"},
                files={"file": (file.filename or "image.jpg", content, file.content_type or "image/jpeg")},
                data={"metadata": f'{{"folder":"{folder}","user_id":"{current_user["id"]}"}}'}
            )
            data = response.json()
            logger.info(f"Cloudflare upload response: {data}")

            if not data.get("success"):
                errors = data.get("errors", [])
                error_msg = errors[0].get("message", "Upload failed") if errors else "Upload failed"
                raise HTTPException(status_code=400, detail=error_msg)

            image_data = data["result"]
            image_id = image_data.get("id", "")
            variants = image_data.get("variants", [])

            return {
                "file_url": cf_delivery(image_id, "public"),
                "thumbnail_url": cf_delivery(image_id, "thumbnail") if "thumbnail" in str(variants) else cf_delivery(image_id, "public"),
                "image_id": image_id,
                "variants": variants,
                "delivery_base": CF_DELIVERY_URL,
            }
    except httpx.RequestError as e:
        logger.error(f"Cloudflare image upload error: {e}")
        raise HTTPException(status_code=500, detail="Failed to upload to Cloudflare")

@api_router.post("/upload/base64-image")
async def upload_base64_image(
    data: dict,
    current_user: dict = Depends(get_current_user)
):
    """Upload base64 image to Cloudflare Images → returns delivery URL"""
    if not CF_ACCOUNT_ID or not CF_API_TOKEN:
        raise HTTPException(status_code=500, detail="Cloudflare not configured")

    base64_str = data.get("image", "")
    folder = data.get("folder", "uploads")

    if not base64_str:
        raise HTTPException(status_code=400, detail="No image data provided")

    if "," in base64_str:
        base64_str = base64_str.split(",")[1]

    try:
        image_bytes = base64.b64decode(base64_str)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 data")

    try:
        async with httpx.AsyncClient(timeout=30.0) as client_http:
            response = await client_http.post(
                CF_IMAGES_URL,
                headers={"Authorization": f"Bearer {CF_API_TOKEN}"},
                files={"file": ("image.jpg", image_bytes, "image/jpeg")},
                data={"metadata": f'{{"folder":"{folder}","user_id":"{current_user["id"]}"}}'}
            )
            data_resp = response.json()
            logger.info(f"Cloudflare base64 upload response: {data_resp}")

            if not data_resp.get("success"):
                errors = data_resp.get("errors", [])
                error_msg = errors[0].get("message", "Upload failed") if errors else "Upload failed"
                raise HTTPException(status_code=400, detail=error_msg)

            image_data = data_resp["result"]
            image_id = image_data.get("id", "")

            return {
                "file_url": cf_delivery(image_id, "public"),
                "image_id": image_id,
            }
    except httpx.RequestError as e:
        logger.error(f"Cloudflare base64 upload error: {e}")
        raise HTTPException(status_code=500, detail="Failed to upload to Cloudflare")

@api_router.post("/upload/video")
async def upload_video(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user)
):
    """Upload video to Cloudflare Stream"""
    if not CF_ACCOUNT_ID or not CF_API_TOKEN:
        raise HTTPException(status_code=500, detail="Cloudflare not configured")
    try:
        content = await file.read()
        async with httpx.AsyncClient(timeout=60.0) as client_http:
            upload_res = await client_http.post(
                f"{CF_STREAM_URL}/direct_upload",
                headers={"Authorization": f"Bearer {CF_API_TOKEN}"},
                json={"maxDurationSeconds": 300}
            )
            upload_data = upload_res.json()
            if not upload_data.get("success"):
                errors = upload_data.get("errors", [])
                raise HTTPException(status_code=400, detail=errors[0].get("message", "Failed") if errors else "Failed")

            video_id = upload_data["result"]["uid"]
            upload_url = upload_data["result"]["uploadURL"]
            await client_http.post(upload_url, files={"file": (file.filename or "video.mp4", content, file.content_type or "video/mp4")})

            return {
                "video_id": video_id,
                "stream_url": f"https://customer-{CF_ACCOUNT_ID[:8]}.cloudflarestream.com/{video_id}/manifest/video.m3u8",
                "thumbnail_url": f"https://customer-{CF_ACCOUNT_ID[:8]}.cloudflarestream.com/{video_id}/thumbnails/thumbnail.jpg",
            }
    except httpx.RequestError as e:
        logger.error(f"Cloudflare video upload error: {e}")
        raise HTTPException(status_code=500, detail="Failed to upload video")


# ===================== REPORTS =====================

class ReportCreate(BaseModel):
    target_type: str  # "post" or "user"
    target_id: str
    reason: str
    details: Optional[str] = None

@api_router.post("/reports")
async def create_report(report: ReportCreate, current_user: dict = Depends(get_current_user)):
    """Report a post or user"""
    report_doc = {
        "id": str(uuid.uuid4()),
        "reporter_id": current_user["id"],
        "target_type": report.target_type,
        "target_id": report.target_id,
        "reason": report.reason,
        "details": report.details,
        "status": "pending",
        "created_at": datetime.utcnow().isoformat(),
    }
    db.reports.insert_one(report_doc)
    return {"message": "Report submitted successfully", "report_id": report_doc["id"]}


# ===================== LIBRARY (Liked/Saved Posts) =====================

@api_router.get("/library/liked")
async def get_liked_posts(current_user: dict = Depends(get_current_user)):
    """Get posts the user has liked"""
    posts = await db.posts.find({"liked_by": current_user["id"]}).sort("created_at", -1).to_list(100)
    return [{k: v for k, v in p.items() if k != "_id"} for p in posts]

@api_router.get("/library/saved")
async def get_saved_posts(current_user: dict = Depends(get_current_user)):
    """Get posts the user has saved"""
    saved = await db.saved_posts.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(100)
    post_ids = [s["post_id"] for s in saved]
    if not post_ids:
        return []
    posts = await db.posts.find({"id": {"$in": post_ids}}).to_list(100)
    return [{k: v for k, v in p.items() if k != "_id"} for p in posts]

@api_router.post("/library/save/{post_id}")
async def save_post(post_id: str, collection: str = "all", current_user: dict = Depends(get_current_user)):
    """Save a post to collection"""
    existing = await db.saved_posts.find_one({"user_id": current_user["id"], "post_id": post_id})
    if existing:
        await db.saved_posts.update_one({"_id": existing["_id"]}, {"$set": {"collection": collection}})
        return {"status": "updated"}
    doc = {
        "id": str(uuid.uuid4()),
        "user_id": current_user["id"],
        "post_id": post_id,
        "collection": collection,
        "created_at": datetime.utcnow().isoformat(),
    }
    await db.saved_posts.insert_one(doc)
    return {"status": "saved"}

@api_router.delete("/library/save/{post_id}")
async def unsave_post(post_id: str, current_user: dict = Depends(get_current_user)):
    """Unsave a post"""
    await db.saved_posts.delete_one({"user_id": current_user["id"], "post_id": post_id})
    return {"status": "removed"}

@api_router.get("/library/collections")
async def get_collections(current_user: dict = Depends(get_current_user)):
    """Get user's save collections with counts"""
    pipeline = [
        {"$match": {"user_id": current_user["id"]}},
        {"$group": {"_id": "$collection", "count": {"$sum": 1}}},
        {"$sort": {"count": -1}},
    ]
    results = await db.saved_posts.aggregate(pipeline).to_list(50)
    return [{"name": r["_id"], "count": r["count"]} for r in results]




# ===================== FRIEND REQUESTS =====================

@api_router.post("/friends/request/{user_id}")
async def send_friend_request(user_id: str, current_user: dict = Depends(get_current_user)):
    """Send a friend request"""
    if user_id == current_user["id"]:
        raise HTTPException(status_code=400, detail="Cannot send friend request to yourself")
    
    target = await db.users.find_one({"id": user_id})
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    
    # Check if already friends
    existing = await db.friends.find_one({
        "$or": [
            {"user_a": current_user["id"], "user_b": user_id},
            {"user_a": user_id, "user_b": current_user["id"]}
        ]
    })
    if existing:
        raise HTTPException(status_code=400, detail="Already friends")
    
    # Check if request already sent
    existing_req = await db.friend_requests.find_one({
        "from_id": current_user["id"],
        "to_id": user_id,
        "status": "pending"
    })
    if existing_req:
        raise HTTPException(status_code=400, detail="Friend request already sent")
    
    # Check if they sent us a request (auto-accept)
    reverse_req = await db.friend_requests.find_one({
        "from_id": user_id,
        "to_id": current_user["id"],
        "status": "pending"
    })
    if reverse_req:
        # Auto accept
        await db.friend_requests.update_one({"id": reverse_req["id"]}, {"$set": {"status": "accepted"}})
        await db.friends.insert_one({
            "id": str(uuid.uuid4()),
            "user_a": current_user["id"],
            "user_b": user_id,
            "created_at": datetime.utcnow().isoformat()
        })
        await create_notification(user_id, "friend_accepted", "Friend Request Accepted",
                                  f"{current_user['username']} accepted your friend request", {})
        return {"status": "accepted", "message": "You are now friends!"}
    
    req_doc = {
        "id": str(uuid.uuid4()),
        "from_id": current_user["id"],
        "from_username": current_user["username"],
        "from_full_name": current_user["full_name"],
        "from_profile_image": current_user.get("profile_image", ""),
        "to_id": user_id,
        "status": "pending",
        "created_at": datetime.utcnow().isoformat()
    }
    await db.friend_requests.insert_one(req_doc)
    
    await create_notification(user_id, "friend_request", "Friend Request",
                              f"{current_user['username']} sent you a friend request", {"request_id": req_doc["id"]})
    
    return {"status": "pending", "request_id": req_doc["id"]}

@api_router.post("/friends/accept/{request_id}")
async def accept_friend_request(request_id: str, current_user: dict = Depends(get_current_user)):
    req = await db.friend_requests.find_one({"id": request_id, "to_id": current_user["id"], "status": "pending"})
    if not req:
        raise HTTPException(status_code=404, detail="Friend request not found")
    
    await db.friend_requests.update_one({"id": request_id}, {"$set": {"status": "accepted"}})
    await db.friends.insert_one({
        "id": str(uuid.uuid4()),
        "user_a": req["from_id"],
        "user_b": current_user["id"],
        "created_at": datetime.utcnow().isoformat()
    })
    
    await create_notification(req["from_id"], "friend_accepted", "Friend Request Accepted",
                              f"{current_user['username']} accepted your friend request", {})
    
    return {"status": "accepted"}

@api_router.post("/friends/reject/{request_id}")
async def reject_friend_request(request_id: str, current_user: dict = Depends(get_current_user)):
    req = await db.friend_requests.find_one({"id": request_id, "to_id": current_user["id"], "status": "pending"})
    if not req:
        raise HTTPException(status_code=404, detail="Friend request not found")
    
    await db.friend_requests.update_one({"id": request_id}, {"$set": {"status": "rejected"}})
    return {"status": "rejected"}

@api_router.get("/friends/requests")
async def get_friend_requests(current_user: dict = Depends(get_current_user)):
    """Get pending friend requests for current user"""
    requests = await db.friend_requests.find({"to_id": current_user["id"], "status": "pending"}).sort("created_at", -1).to_list(100)
    return [{k: v for k, v in r.items() if k != "_id"} for r in requests]

@api_router.get("/friends")
async def get_friends(current_user: dict = Depends(get_current_user)):
    """Get current user's friends list"""
    friendships = await db.friends.find({
        "$or": [{"user_a": current_user["id"]}, {"user_b": current_user["id"]}]
    }).to_list(500)
    
    friend_ids = []
    for f in friendships:
        fid = f["user_b"] if f["user_a"] == current_user["id"] else f["user_a"]
        friend_ids.append(fid)
    
    friends = await db.users.find({"id": {"$in": friend_ids}}).to_list(500)
    return [{k: v for k, v in u.items() if k not in ("_id", "hashed_password")} for u in friends]

@api_router.get("/friends/status/{user_id}")
async def get_friendship_status(user_id: str, current_user: dict = Depends(get_current_user)):
    """Check friendship status with another user"""
    # Check if already friends
    friendship = await db.friends.find_one({
        "$or": [
            {"user_a": current_user["id"], "user_b": user_id},
            {"user_a": user_id, "user_b": current_user["id"]}
        ]
    })
    if friendship:
        return {"status": "friends"}
    
    # Check if request pending (I sent)
    sent = await db.friend_requests.find_one({
        "from_id": current_user["id"], "to_id": user_id, "status": "pending"
    })
    if sent:
        return {"status": "pending_sent", "request_id": sent["id"]}
    
    # Check if request pending (they sent)
    received = await db.friend_requests.find_one({
        "from_id": user_id, "to_id": current_user["id"], "status": "pending"
    })
    if received:
        return {"status": "pending_received", "request_id": received["id"]}
    
    return {"status": "none"}

@api_router.delete("/friends/{user_id}")
async def remove_friend(user_id: str, current_user: dict = Depends(get_current_user)):
    """Remove a friend"""
    result = await db.friends.delete_one({
        "$or": [
            {"user_a": current_user["id"], "user_b": user_id},
            {"user_a": user_id, "user_b": current_user["id"]}
        ]
    })
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Friendship not found")
    return {"status": "removed"}


# ===================== GOOGLE MAPS PLACES API =====================

@api_router.get("/google-places/nearby")
async def google_places_nearby(
    lat: float = Query(40.7128),
    lng: float = Query(-74.0060),
    radius: int = Query(5000),
    type: str = Query("restaurant"),
    keyword: str = Query(""),
):
    """Fetch nearby places from Google Places API with photos"""
    if not GOOGLE_MAPS_API_KEY:
        raise HTTPException(status_code=500, detail="Google Maps API not configured")

    url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
    params = {
        "location": f"{lat},{lng}",
        "radius": radius,
        "type": type,
        "key": GOOGLE_MAPS_API_KEY,
    }
    if keyword:
        params["keyword"] = keyword

    try:
        async with httpx.AsyncClient(timeout=15.0) as client_http:
            response = await client_http.get(url, params=params)
            data = response.json()

            if data.get("status") not in ("OK", "ZERO_RESULTS"):
                raise HTTPException(status_code=400, detail=data.get("error_message", "Places API error"))

            results = []
            for place in data.get("results", []):
                photo_url = None
                if place.get("photos"):
                    photo_ref = place["photos"][0].get("photo_reference")
                    if photo_ref:
                        photo_url = f"https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference={photo_ref}&key={GOOGLE_MAPS_API_KEY}"

                results.append({
                    "place_id": place.get("place_id"),
                    "name": place.get("name"),
                    "address": place.get("vicinity", ""),
                    "rating": place.get("rating", 0),
                    "user_ratings_total": place.get("user_ratings_total", 0),
                    "price_level": place.get("price_level"),
                    "types": place.get("types", []),
                    "lat": place["geometry"]["location"]["lat"],
                    "lng": place["geometry"]["location"]["lng"],
                    "photo_url": photo_url,
                    "open_now": place.get("opening_hours", {}).get("open_now"),
                    "business_status": place.get("business_status"),
                })

            return results
    except httpx.RequestError as e:
        logger.error(f"Google Places API error: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch places")

@api_router.get("/google-places/{place_id}")
async def google_place_detail(place_id: str):
    """Fetch place detail from Google Places API"""
    if not GOOGLE_MAPS_API_KEY:
        raise HTTPException(status_code=500, detail="Google Maps API not configured")

    url = "https://maps.googleapis.com/maps/api/place/details/json"
    params = {
        "place_id": place_id,
        "fields": "name,formatted_address,formatted_phone_number,rating,user_ratings_total,reviews,photos,opening_hours,website,price_level,types,geometry,url",
        "key": GOOGLE_MAPS_API_KEY,
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client_http:
            response = await client_http.get(url, params=params)
            data = response.json()

            if data.get("status") != "OK":
                raise HTTPException(status_code=400, detail=data.get("error_message", "Place not found"))

            place = data["result"]
            photos = []
            for p in place.get("photos", [])[:6]:
                photo_ref = p.get("photo_reference")
                if photo_ref:
                    photos.append(f"https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference={photo_ref}&key={GOOGLE_MAPS_API_KEY}")

            reviews = []
            for r in place.get("reviews", [])[:5]:
                reviews.append({
                    "author": r.get("author_name"),
                    "rating": r.get("rating"),
                    "text": r.get("text"),
                    "time": r.get("relative_time_description"),
                    "profile_photo": r.get("profile_photo_url"),
                })

            hours = []
            if place.get("opening_hours"):
                hours = place["opening_hours"].get("weekday_text", [])

            return {
                "place_id": place_id,
                "name": place.get("name"),
                "address": place.get("formatted_address"),
                "phone": place.get("formatted_phone_number"),
                "rating": place.get("rating", 0),
                "user_ratings_total": place.get("user_ratings_total", 0),
                "website": place.get("website"),
                "google_maps_url": place.get("url"),
                "price_level": place.get("price_level"),
                "types": place.get("types", []),
                "lat": place.get("geometry", {}).get("location", {}).get("lat"),
                "lng": place.get("geometry", {}).get("location", {}).get("lng"),
                "photos": photos,
                "reviews": reviews,
                "hours": hours,
                "open_now": place.get("opening_hours", {}).get("open_now"),
            }
    except httpx.RequestError as e:
        logger.error(f"Google Places detail error: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch place details")


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
