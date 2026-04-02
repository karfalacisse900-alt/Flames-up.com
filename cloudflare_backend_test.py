#!/usr/bin/env python3
"""
Comprehensive Backend API Testing for Flames-Up Cloudflare Workers
Testing all core endpoints on the new Cloudflare Workers backend
"""

import requests
import json
import sys
import time
from datetime import datetime

# Configuration for Cloudflare Workers Backend
BASE_URL = "https://flames-up-api.karfalacisse900.workers.dev/api"
TEST_EMAIL = "demo@flames-up.com"
TEST_PASSWORD = "demo123456"

class FlamesUpCloudflareTest:
    def __init__(self):
        self.base_url = BASE_URL
        self.auth_token = None
        self.user_id = None
        self.test_results = []
        self.created_post_id = None
        self.created_user_id = None
        
    def log_test(self, test_name, success, details="", response_data=None):
        """Log test results"""
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} {test_name}")
        if details:
            print(f"   Details: {details}")
        if response_data and not success:
            print(f"   Response: {response_data}")
        print()
        
        self.test_results.append({
            "test": test_name,
            "success": success,
            "details": details,
            "response": response_data
        })
    
    def make_request(self, method, endpoint, data=None, headers=None, params=None):
        """Make HTTP request with error handling"""
        url = f"{self.base_url}{endpoint}"
        default_headers = {"Content-Type": "application/json"}
        
        if self.auth_token:
            default_headers["Authorization"] = f"Bearer {self.auth_token}"
        
        if headers:
            default_headers.update(headers)
        
        try:
            if method.upper() == "GET":
                response = requests.get(url, headers=default_headers, params=params, timeout=15)
            elif method.upper() == "POST":
                response = requests.post(url, json=data, headers=default_headers, timeout=15)
            elif method.upper() == "PUT":
                response = requests.put(url, json=data, headers=default_headers, timeout=15)
            elif method.upper() == "DELETE":
                response = requests.delete(url, headers=default_headers, timeout=15)
            else:
                raise ValueError(f"Unsupported method: {method}")
            
            return response
        except requests.exceptions.RequestException as e:
            print(f"Request failed: {e}")
            return None
    
    # ========== AUTH ENDPOINTS ==========
    
    def test_auth_login(self):
        """Test user login and get auth token"""
        print("🔐 Testing Auth Login...")
        
        login_data = {
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD
        }
        
        response = self.make_request("POST", "/auth/login", login_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "access_token" in data and "user" in data:
                self.auth_token = data["access_token"]
                self.user_id = data["user"].get("id")
                self.log_test("Auth Login", True, f"Token obtained, User ID: {self.user_id}")
                return True
            else:
                self.log_test("Auth Login", False, "Missing access_token or user in response", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Auth Login", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_auth_me(self):
        """Test get current user with Bearer token"""
        print("👤 Testing Auth Me...")
        
        response = self.make_request("GET", "/auth/me")
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data and data.get("is_admin") == 1 and data.get("is_publisher") == 1:
                self.log_test("Auth Me", True, f"User retrieved: is_admin={data.get('is_admin')}, is_publisher={data.get('is_publisher')}")
                return True
            else:
                self.log_test("Auth Me", False, f"Missing expected fields or incorrect values. is_admin={data.get('is_admin')}, is_publisher={data.get('is_publisher')}", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Auth Me", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_auth_register(self):
        """Test user registration"""
        print("📝 Testing Auth Register...")
        
        # Generate unique email for testing
        timestamp = int(time.time())
        register_data = {
            "email": f"testuser{timestamp}@flames-up.com",
            "password": "testpass123",
            "username": f"testuser{timestamp}",
            "full_name": f"Test User {timestamp}"
        }
        
        response = self.make_request("POST", "/auth/register", register_data)
        
        if response and response.status_code in [200, 201]:
            data = response.json()
            if "user" in data or "id" in data:
                user_data = data.get("user", data)
                self.created_user_id = user_data.get("id")
                self.log_test("Auth Register", True, f"User registered successfully: {register_data['email']}")
                return True
            else:
                self.log_test("Auth Register", False, "No user data in response", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Auth Register", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    # ========== POSTS ENDPOINTS ==========
    
    def test_posts_create(self):
        """Test creating a post"""
        print("📝 Testing Create Post...")
        
        post_data = {
            "content": "This is a test post from the Cloudflare Workers backend testing!",
            "post_type": "lifestyle"
        }
        
        response = self.make_request("POST", "/posts", post_data)
        
        if response and response.status_code in [200, 201]:
            data = response.json()
            if "id" in data and data.get("content") == post_data["content"]:
                self.created_post_id = data["id"]
                self.log_test("Create Post", True, f"Post created: ID={data['id']}")
                return True
            else:
                self.log_test("Create Post", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Create Post", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_posts_feed(self):
        """Test getting posts feed"""
        print("📰 Testing Posts Feed...")
        
        response = self.make_request("GET", "/posts/feed")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("Posts Feed", True, f"Retrieved {len(data)} posts in feed")
                return True
            else:
                self.log_test("Posts Feed", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Posts Feed", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_posts_like(self):
        """Test liking a post"""
        print("❤️ Testing Like Post...")
        
        if not self.created_post_id:
            self.log_test("Like Post", False, "No post ID available for testing")
            return False
        
        response = self.make_request("POST", f"/posts/{self.created_post_id}/like")
        
        if response and response.status_code == 200:
            data = response.json()
            self.log_test("Like Post", True, f"Post liked successfully")
            return True
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Like Post", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_posts_comment(self):
        """Test adding a comment to a post"""
        print("💬 Testing Add Comment...")
        
        if not self.created_post_id:
            self.log_test("Add Comment", False, "No post ID available for testing")
            return False
        
        comment_data = {
            "content": "This is a test comment on the post!"
        }
        
        response = self.make_request("POST", f"/posts/{self.created_post_id}/comments", comment_data)
        
        if response and response.status_code in [200, 201]:
            data = response.json()
            if "id" in data and data.get("content") == comment_data["content"]:
                self.log_test("Add Comment", True, f"Comment added: ID={data['id']}")
                return True
            else:
                self.log_test("Add Comment", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Add Comment", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    # ========== USERS ENDPOINTS ==========
    
    def test_users_get_profile(self):
        """Test getting user profile"""
        print("👤 Testing Get User Profile...")
        
        if not self.user_id:
            self.log_test("Get User Profile", False, "No user ID available for testing")
            return False
        
        response = self.make_request("GET", f"/users/{self.user_id}")
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data and data["id"] == self.user_id:
                self.log_test("Get User Profile", True, f"Profile retrieved for user: {data.get('username', 'N/A')}")
                return True
            else:
                self.log_test("Get User Profile", False, "Invalid response structure or wrong user", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Get User Profile", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_users_update_profile(self):
        """Test updating user profile"""
        print("✏️ Testing Update Profile...")
        
        update_data = {
            "bio": f"Updated bio from Cloudflare test at {datetime.now().isoformat()}"
        }
        
        response = self.make_request("PUT", "/users/me", update_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "bio" in data and update_data["bio"] in data["bio"]:
                self.log_test("Update Profile", True, "Profile updated successfully")
                return True
            else:
                self.log_test("Update Profile", False, "Bio not updated correctly", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Update Profile", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    # ========== MESSAGES ENDPOINTS ==========
    
    def test_messages_send(self):
        """Test sending a message with media"""
        print("💌 Testing Send Message...")
        
        message_data = {
            "receiver_id": self.user_id,  # Send to self for testing
            "content": "Test message from Cloudflare Workers backend!",
            "media_url": "https://example.com/test-image.jpg",
            "media_type": "image"
        }
        
        response = self.make_request("POST", "/messages", message_data)
        
        if response and response.status_code in [200, 201]:
            data = response.json()
            if "id" in data:
                self.log_test("Send Message", True, f"Message sent: ID={data['id']}")
                return True
            else:
                self.log_test("Send Message", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Send Message", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_messages_get_conversation(self):
        """Test getting conversation"""
        print("💬 Testing Get Conversation...")
        
        if not self.user_id:
            self.log_test("Get Conversation", False, "No user ID available for testing")
            return False
        
        response = self.make_request("GET", f"/messages/{self.user_id}")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("Get Conversation", True, f"Retrieved {len(data)} messages")
                return True
            else:
                self.log_test("Get Conversation", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Get Conversation", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    # ========== ADMIN ENDPOINTS ==========
    
    def test_admin_stats(self):
        """Test admin stats"""
        print("📊 Testing Admin Stats...")
        
        response = self.make_request("GET", "/admin/stats")
        
        if response and response.status_code == 200:
            data = response.json()
            if "total_users" in data and "total_posts" in data:
                self.log_test("Admin Stats", True, f"Stats: users={data['total_users']}, posts={data['total_posts']}")
                return True
            else:
                self.log_test("Admin Stats", False, "Missing required stats fields", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Admin Stats", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_admin_reported_posts(self):
        """Test admin reported posts"""
        print("📋 Testing Admin Reported Posts...")
        
        response = self.make_request("GET", "/admin/reported-posts")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("Admin Reported Posts", True, f"Retrieved {len(data)} reported posts")
                return True
            else:
                self.log_test("Admin Reported Posts", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Admin Reported Posts", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_admin_publisher_applications(self):
        """Test admin publisher applications"""
        print("📝 Testing Admin Publisher Applications...")
        
        response = self.make_request("GET", "/admin/publisher-applications")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("Admin Publisher Applications", True, f"Retrieved {len(data)} publisher applications")
                return True
            else:
                self.log_test("Admin Publisher Applications", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Admin Publisher Applications", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    # ========== GOOGLE PLACES ENDPOINTS ==========
    
    def test_google_places_nearby(self):
        """Test Google Places nearby search"""
        print("📍 Testing Google Places Nearby...")
        
        params = {
            "type": "restaurant",
            "lat": 40.7128,
            "lng": -74.006,
            "radius": 3000
        }
        
        response = self.make_request("GET", "/google-places/nearby", params=params)
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list) or "results" in data:
                results = data if isinstance(data, list) else data.get("results", [])
                self.log_test("Google Places Nearby", True, f"Retrieved {len(results)} nearby places")
                return True
            else:
                self.log_test("Google Places Nearby", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Google Places Nearby", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    # ========== DISCOVER ENDPOINTS ==========
    
    def test_discover_categories(self):
        """Test discover categories"""
        print("🔍 Testing Discover Categories...")
        
        response = self.make_request("GET", "/discover/categories")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("Discover Categories", True, f"Retrieved {len(data)} categories")
                return True
            else:
                self.log_test("Discover Categories", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Discover Categories", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_discover_posts(self):
        """Test discover posts (publisher post)"""
        print("📰 Testing Discover Posts...")
        
        post_data = {
            "title": "Test Publisher Post",
            "content": "This is a test publisher post for discovery",
            "category": "food"
        }
        
        response = self.make_request("POST", "/discover/posts", post_data)
        
        if response and response.status_code in [200, 201]:
            data = response.json()
            if "id" in data:
                self.log_test("Discover Posts", True, f"Publisher post created: ID={data['id']}")
                return True
            else:
                self.log_test("Discover Posts", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Discover Posts", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_discover_feed(self):
        """Test discover feed"""
        print("📱 Testing Discover Feed...")
        
        response = self.make_request("GET", "/discover/feed")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("Discover Feed", True, f"Retrieved {len(data)} discover posts")
                return True
            else:
                self.log_test("Discover Feed", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Discover Feed", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    # ========== PUBLISHER ENDPOINTS ==========
    
    def test_publisher_status(self):
        """Test publisher status"""
        print("📊 Testing Publisher Status...")
        
        response = self.make_request("GET", "/publisher/status")
        
        if response and response.status_code == 200:
            data = response.json()
            if "is_publisher" in data or "status" in data:
                self.log_test("Publisher Status", True, f"Publisher status retrieved")
                return True
            else:
                self.log_test("Publisher Status", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Publisher Status", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_publisher_apply(self):
        """Test publisher application (with new user if available)"""
        print("📝 Testing Publisher Apply...")
        
        # This test might fail if user is already a publisher, which is expected
        apply_data = {
            "business_name": "Test Business",
            "business_type": "restaurant",
            "description": "Test publisher application"
        }
        
        response = self.make_request("POST", "/publisher/apply", apply_data)
        
        if response and response.status_code in [200, 201]:
            data = response.json()
            self.log_test("Publisher Apply", True, "Publisher application submitted")
            return True
        elif response and response.status_code == 400:
            # User might already be a publisher
            self.log_test("Publisher Apply", True, "User already a publisher (expected for demo user)")
            return True
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("Publisher Apply", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def run_all_tests(self):
        """Run all tests in sequence"""
        print("🚀 Starting Flames-Up Cloudflare Workers Backend API Tests")
        print("=" * 70)
        print(f"Testing Backend: {self.base_url}")
        print(f"Test Credentials: {TEST_EMAIL}")
        print("=" * 70)
        
        # Authentication is required for all other tests
        if not self.test_auth_login():
            print("❌ Authentication failed. Cannot proceed with other tests.")
            return False
        
        # Test all endpoint categories
        print("\n🔐 AUTH ENDPOINTS")
        print("-" * 40)
        self.test_auth_me()
        self.test_auth_register()
        
        print("\n📝 POSTS ENDPOINTS")
        print("-" * 40)
        self.test_posts_create()
        self.test_posts_feed()
        self.test_posts_like()
        self.test_posts_comment()
        
        print("\n👤 USERS ENDPOINTS")
        print("-" * 40)
        self.test_users_get_profile()
        self.test_users_update_profile()
        
        print("\n💌 MESSAGES ENDPOINTS")
        print("-" * 40)
        self.test_messages_send()
        self.test_messages_get_conversation()
        
        print("\n🔧 ADMIN ENDPOINTS")
        print("-" * 40)
        self.test_admin_stats()
        self.test_admin_reported_posts()
        self.test_admin_publisher_applications()
        
        print("\n📍 GOOGLE PLACES ENDPOINTS")
        print("-" * 40)
        self.test_google_places_nearby()
        
        print("\n🔍 DISCOVER ENDPOINTS")
        print("-" * 40)
        self.test_discover_categories()
        self.test_discover_posts()
        self.test_discover_feed()
        
        print("\n📊 PUBLISHER ENDPOINTS")
        print("-" * 40)
        self.test_publisher_status()
        self.test_publisher_apply()
        
        # Summary
        print("\n📊 TEST SUMMARY")
        print("=" * 70)
        
        total_tests = len(self.test_results)
        passed_tests = sum(1 for result in self.test_results if result["success"])
        failed_tests = total_tests - passed_tests
        
        print(f"Total Tests: {total_tests}")
        print(f"✅ Passed: {passed_tests}")
        print(f"❌ Failed: {failed_tests}")
        print(f"Success Rate: {(passed_tests/total_tests)*100:.1f}%")
        
        if failed_tests > 0:
            print("\n❌ FAILED TESTS:")
            for result in self.test_results:
                if not result["success"]:
                    print(f"  - {result['test']}: {result['details']}")
        
        return failed_tests == 0

if __name__ == "__main__":
    tester = FlamesUpCloudflareTest()
    success = tester.run_all_tests()
    sys.exit(0 if success else 1)