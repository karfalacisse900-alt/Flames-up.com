#!/usr/bin/env python3
"""
Comprehensive Backend API Testing for Flames-Up Cloudflare Workers
Testing all endpoints as specified in the review request
"""

import requests
import json
import sys
import time
import base64
from datetime import datetime

# Configuration
BASE_URL = "https://flames-up-api.karfalacisse900.workers.dev/api"
TEST_EMAIL = "demo@flames-up.com"
TEST_PASSWORD = "demo123456"

class CloudflareBackendTester:
    def __init__(self):
        self.base_url = BASE_URL
        self.auth_token = None
        self.user_id = None
        self.test_results = []
        self.created_post_id = None
        
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
    
    def make_request(self, method, endpoint, data=None, headers=None):
        """Make HTTP request with error handling"""
        url = f"{self.base_url}{endpoint}"
        default_headers = {"Content-Type": "application/json"}
        
        if self.auth_token:
            default_headers["Authorization"] = f"Bearer {self.auth_token}"
        
        if headers:
            default_headers.update(headers)
        
        try:
            if method.upper() == "GET":
                response = requests.get(url, headers=default_headers, timeout=15)
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
    
    def test_auth_login(self):
        """Test POST /api/auth/login"""
        print("🔐 Testing Authentication Login...")
        
        login_data = {
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD
        }
        
        response = self.make_request("POST", "/auth/login", login_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "access_token" in data and "user" in data:
                self.auth_token = data["access_token"]
                user = data["user"]
                self.user_id = user.get("id")
                self.log_test("POST /api/auth/login", True, 
                            f"Token obtained, User ID: {self.user_id}, Admin: {user.get('is_admin')}, Publisher: {user.get('is_publisher')}")
                return True
            else:
                self.log_test("POST /api/auth/login", False, "Missing access_token or user in response", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("POST /api/auth/login", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_auth_me(self):
        """Test GET /api/auth/me"""
        print("👤 Testing Get Current User...")
        
        response = self.make_request("GET", "/auth/me")
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data and data.get("is_admin") == 1 and data.get("is_publisher") == 1:
                self.log_test("GET /api/auth/me", True, 
                            f"User details retrieved: ID={data['id']}, Admin={data.get('is_admin')}, Publisher={data.get('is_publisher')}")
                return True
            else:
                self.log_test("GET /api/auth/me", False, "User not admin or publisher as expected", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/auth/me", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_create_post(self):
        """Test POST /api/posts"""
        print("📝 Testing Create Post...")
        
        post_data = {
            "content": "This is a test post from the Cloudflare Workers backend testing suite!",
            "post_type": "lifestyle"
        }
        
        response = self.make_request("POST", "/posts", post_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data and data.get("content") == post_data["content"]:
                self.created_post_id = data["id"]
                self.log_test("POST /api/posts", True, f"Post created with ID: {self.created_post_id}")
                return True
            else:
                self.log_test("POST /api/posts", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("POST /api/posts", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_get_feed(self):
        """Test GET /api/posts/feed"""
        print("📰 Testing Get Feed...")
        
        response = self.make_request("GET", "/posts/feed")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("GET /api/posts/feed", True, f"Feed retrieved with {len(data)} posts")
                return True
            else:
                self.log_test("GET /api/posts/feed", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/posts/feed", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_like_post(self):
        """Test POST /api/posts/{postId}/like"""
        print("❤️ Testing Like Post...")
        
        if not self.created_post_id:
            self.log_test("POST /api/posts/{postId}/like", False, "No post ID available for testing")
            return False
        
        response = self.make_request("POST", f"/posts/{self.created_post_id}/like")
        
        if response and response.status_code == 200:
            data = response.json()
            self.log_test("POST /api/posts/{postId}/like", True, f"Post liked successfully: {data}")
            return True
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("POST /api/posts/{postId}/like", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_add_comment(self):
        """Test POST /api/posts/{postId}/comments"""
        print("💬 Testing Add Comment...")
        
        if not self.created_post_id:
            self.log_test("POST /api/posts/{postId}/comments", False, "No post ID available for testing")
            return False
        
        comment_data = {
            "content": "This is a test comment on the post!"
        }
        
        response = self.make_request("POST", f"/posts/{self.created_post_id}/comments", comment_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data and data.get("content") == comment_data["content"]:
                self.log_test("POST /api/posts/{postId}/comments", True, f"Comment added with ID: {data['id']}")
                return True
            else:
                self.log_test("POST /api/posts/{postId}/comments", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("POST /api/posts/{postId}/comments", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_get_user_profile(self):
        """Test GET /api/users/{userId}"""
        print("👤 Testing Get User Profile...")
        
        if not self.user_id:
            self.log_test("GET /api/users/{userId}", False, "No user ID available for testing")
            return False
        
        response = self.make_request("GET", f"/users/{self.user_id}")
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data and data["id"] == self.user_id:
                self.log_test("GET /api/users/{userId}", True, f"User profile retrieved: {data.get('email', 'N/A')}")
                return True
            else:
                self.log_test("GET /api/users/{userId}", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/users/{userId}", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_update_profile(self):
        """Test PUT /api/users/me"""
        print("✏️ Testing Update Profile...")
        
        update_data = {
            "bio": f"Updated bio from test at {datetime.now().isoformat()}"
        }
        
        response = self.make_request("PUT", "/users/me", update_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "bio" in data and update_data["bio"] in data["bio"]:
                self.log_test("PUT /api/users/me", True, f"Profile updated successfully")
                return True
            else:
                self.log_test("PUT /api/users/me", False, "Profile update not reflected", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("PUT /api/users/me", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_send_message(self):
        """Test POST /api/messages"""
        print("💌 Testing Send Message...")
        
        message_data = {
            "receiver_id": self.user_id,  # Send to self for testing
            "content": "Test message from Cloudflare Workers backend test",
            "media_url": "https://example.com/test-image.jpg",
            "media_type": "image"
        }
        
        response = self.make_request("POST", "/messages", message_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data and data.get("content") == message_data["content"]:
                self.log_test("POST /api/messages", True, f"Message sent with ID: {data['id']}")
                return True
            else:
                self.log_test("POST /api/messages", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("POST /api/messages", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_get_conversation(self):
        """Test GET /api/messages/{userId}"""
        print("💬 Testing Get Conversation...")
        
        if not self.user_id:
            self.log_test("GET /api/messages/{userId}", False, "No user ID available for testing")
            return False
        
        response = self.make_request("GET", f"/messages/{self.user_id}")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("GET /api/messages/{userId}", True, f"Conversation retrieved with {len(data)} messages")
                return True
            else:
                self.log_test("GET /api/messages/{userId}", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/messages/{userId}", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_admin_stats(self):
        """Test GET /api/admin/stats"""
        print("📊 Testing Admin Stats...")
        
        response = self.make_request("GET", "/admin/stats")
        
        if response and response.status_code == 200:
            data = response.json()
            if "total_users" in data and "total_posts" in data:
                self.log_test("GET /api/admin/stats", True, f"Stats retrieved: {data}")
                return True
            else:
                self.log_test("GET /api/admin/stats", False, "Missing expected fields", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/admin/stats", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_admin_reported_posts(self):
        """Test GET /api/admin/reported-posts"""
        print("📋 Testing Admin Reported Posts...")
        
        response = self.make_request("GET", "/admin/reported-posts")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("GET /api/admin/reported-posts", True, f"Retrieved {len(data)} reported posts")
                return True
            else:
                self.log_test("GET /api/admin/reported-posts", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/admin/reported-posts", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_admin_publisher_applications(self):
        """Test GET /api/admin/publisher-applications"""
        print("📝 Testing Admin Publisher Applications...")
        
        response = self.make_request("GET", "/admin/publisher-applications")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("GET /api/admin/publisher-applications", True, f"Retrieved {len(data)} publisher applications")
                return True
            else:
                self.log_test("GET /api/admin/publisher-applications", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/admin/publisher-applications", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_google_places_nearby(self):
        """Test GET /api/google-places/nearby"""
        print("📍 Testing Google Places Nearby...")
        
        response = self.make_request("GET", "/google-places/nearby?type=restaurant&lat=40.7128&lng=-74.006&radius=3000")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("GET /api/google-places/nearby", True, f"Retrieved {len(data)} nearby places")
                return True
            else:
                self.log_test("GET /api/google-places/nearby", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/google-places/nearby", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_discover_categories(self):
        """Test GET /api/discover/categories"""
        print("🔍 Testing Discover Categories...")
        
        response = self.make_request("GET", "/discover/categories")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("GET /api/discover/categories", True, f"Retrieved {len(data)} categories")
                return True
            else:
                self.log_test("GET /api/discover/categories", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/discover/categories", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_discover_feed(self):
        """Test GET /api/discover/feed"""
        print("🌟 Testing Discover Feed...")
        
        response = self.make_request("GET", "/discover/feed")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("GET /api/discover/feed", True, f"Retrieved {len(data)} discover posts")
                return True
            else:
                self.log_test("GET /api/discover/feed", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/discover/feed", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_publisher_apply_new_user(self):
        """Test POST /api/publisher/apply with a new user"""
        print("📋 Testing Publisher Apply (New User)...")
        
        # First register a new user
        new_user_email = f"testpublisher{int(time.time())}@flames-up.com"
        register_data = {
            "email": new_user_email,
            "password": "testpass123",
            "username": f"testpub{int(time.time())}",
            "full_name": "Test Publisher User"
        }
        
        # Register new user
        register_response = self.make_request("POST", "/auth/register", register_data)
        if not register_response or register_response.status_code != 200:
            self.log_test("POST /api/publisher/apply", False, "Failed to register new test user for publisher application")
            return False
        
        # Login as new user
        login_data = {
            "email": new_user_email,
            "password": "testpass123"
        }
        
        login_response = self.make_request("POST", "/auth/login", login_data)
        if not login_response or login_response.status_code != 200:
            self.log_test("POST /api/publisher/apply", False, "Failed to login as new test user")
            return False
        
        # Store original token and set new user token
        original_token = self.auth_token
        new_user_data = login_response.json()
        self.auth_token = new_user_data["access_token"]
        
        # Apply for publisher status
        application_data = {
            "business_name": "Test Restaurant & Cafe",
            "category": "restaurant",
            "about": "A test restaurant for publisher application testing. We serve delicious food and great coffee.",
            "phone": "+1-555-123-4567",
            "why_publish": "We want to share our daily specials and connect with food lovers in our community."
        }
        
        response = self.make_request("POST", "/publisher/apply", application_data)
        
        # Restore original token
        self.auth_token = original_token
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data or "message" in data:
                self.log_test("POST /api/publisher/apply", True, f"Publisher application submitted successfully")
                return True
            else:
                self.log_test("POST /api/publisher/apply", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("POST /api/publisher/apply", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_upload_image(self):
        """Test POST /api/upload/image"""
        print("🖼️ Testing Upload Image...")
        
        # Create a small test image in base64
        test_image_base64 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        
        upload_data = {
            "image": test_image_base64
        }
        
        response = self.make_request("POST", "/upload/image", upload_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "url" in data or "base64_fallback" in data:
                url_type = "cloudflare_images" if "url" in data else "base64_fallback"
                self.log_test("POST /api/upload/image", True, f"Image uploaded successfully, returned {url_type}")
                return True
            else:
                self.log_test("POST /api/upload/image", False, "No URL or fallback in response", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("POST /api/upload/image", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_get_statuses(self):
        """Test GET /api/statuses"""
        print("📱 Testing Get Statuses...")
        
        response = self.make_request("GET", "/statuses")
        
        if response and response.status_code == 200:
            data = response.json()
            if isinstance(data, list):
                self.log_test("GET /api/statuses", True, f"Retrieved {len(data)} statuses")
                return True
            else:
                self.log_test("GET /api/statuses", False, "Response is not a list", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("GET /api/statuses", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def test_create_status(self):
        """Test POST /api/statuses"""
        print("✨ Testing Create Status...")
        
        status_data = {
            "content": "Testing status creation from Cloudflare Workers backend!",
            "background_color": "#FF6B6B"
        }
        
        response = self.make_request("POST", "/statuses", status_data)
        
        if response and response.status_code == 200:
            data = response.json()
            if "id" in data and data.get("content") == status_data["content"]:
                self.log_test("POST /api/statuses", True, f"Status created with ID: {data['id']}")
                return True
            else:
                self.log_test("POST /api/statuses", False, "Invalid response structure", data)
                return False
        else:
            error_msg = response.json() if response else "No response"
            self.log_test("POST /api/statuses", False, f"Status: {response.status_code if response else 'No response'}", error_msg)
            return False
    
    def run_all_tests(self):
        """Run all tests in sequence"""
        print("🚀 Starting Flames-Up Cloudflare Workers Backend API Tests")
        print("=" * 80)
        print(f"Backend URL: {self.base_url}")
        print(f"Test Credentials: {TEST_EMAIL}")
        print("=" * 80)
        
        # Authentication is required for all other tests
        if not self.test_auth_login():
            print("❌ Authentication failed. Cannot proceed with other tests.")
            return False
        
        # Test auth endpoints
        print("\n🔐 AUTHENTICATION TESTS")
        print("-" * 50)
        self.test_auth_me()
        
        # Test core post functionality
        print("\n📝 POST MANAGEMENT TESTS")
        print("-" * 50)
        self.test_create_post()
        self.test_get_feed()
        self.test_like_post()
        self.test_add_comment()
        
        # Test user management
        print("\n👤 USER MANAGEMENT TESTS")
        print("-" * 50)
        self.test_get_user_profile()
        self.test_update_profile()
        
        # Test messaging
        print("\n💌 MESSAGING TESTS")
        print("-" * 50)
        self.test_send_message()
        self.test_get_conversation()
        
        # Test admin endpoints
        print("\n🔧 ADMIN TESTS")
        print("-" * 50)
        self.test_admin_stats()
        self.test_admin_reported_posts()
        self.test_admin_publisher_applications()
        
        # Test external integrations
        print("\n🌐 EXTERNAL INTEGRATION TESTS")
        print("-" * 50)
        self.test_google_places_nearby()
        
        # Test discovery
        print("\n🔍 DISCOVERY TESTS")
        print("-" * 50)
        self.test_discover_categories()
        self.test_discover_feed()
        
        # Test publisher functionality
        print("\n📋 PUBLISHER TESTS")
        print("-" * 50)
        self.test_publisher_apply_new_user()
        
        # Test file upload
        print("\n🖼️ FILE UPLOAD TESTS")
        print("-" * 50)
        self.test_upload_image()
        
        # Test status/stories
        print("\n📱 STATUS/STORIES TESTS")
        print("-" * 50)
        self.test_get_statuses()
        self.test_create_status()
        
        # Summary
        print("\n📊 TEST SUMMARY")
        print("=" * 80)
        
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
        
        print("\n" + "=" * 80)
        return failed_tests == 0

if __name__ == "__main__":
    tester = CloudflareBackendTester()
    success = tester.run_all_tests()
    sys.exit(0 if success else 1)