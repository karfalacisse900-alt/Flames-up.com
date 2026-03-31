#!/usr/bin/env python3
"""
Comprehensive Backend API Tests for Flames-Up Social Media App
Tests all API endpoints with proper authentication flow
"""

import requests
import json
import time
from datetime import datetime
from typing import Dict, Any, Optional

class FlamesUpAPITester:
    def __init__(self, base_url: str = "https://flames-up-preview.preview.emergentagent.com/api"):
        self.base_url = base_url
        self.session = requests.Session()
        self.auth_token = None
        self.current_user = None
        self.test_results = []
        
        # Test credentials from test_credentials.md
        self.demo_user = {
            "email": "demo@flames-up.com",
            "password": "demo123456",
            "username": "demouser",
            "full_name": "Demo User"
        }
        
        self.test_user = {
            "email": "test@flames-up.com", 
            "password": "test123456",
            "username": "testuser",
            "full_name": "Test User"
        }

    def log_result(self, test_name: str, success: bool, details: str = "", response_data: Any = None):
        """Log test results"""
        result = {
            "test": test_name,
            "success": success,
            "details": details,
            "timestamp": datetime.now().isoformat(),
            "response_data": response_data
        }
        self.test_results.append(result)
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} {test_name}: {details}")

    def make_request(self, method: str, endpoint: str, data: Dict = None, headers: Dict = None) -> requests.Response:
        """Make HTTP request with proper headers"""
        url = f"{self.base_url}{endpoint}"
        req_headers = {"Content-Type": "application/json"}
        
        if self.auth_token:
            req_headers["Authorization"] = f"Bearer {self.auth_token}"
            
        if headers:
            req_headers.update(headers)
            
        try:
            if method.upper() == "GET":
                response = self.session.get(url, headers=req_headers, timeout=30)
            elif method.upper() == "POST":
                response = self.session.post(url, json=data, headers=req_headers, timeout=30)
            elif method.upper() == "PUT":
                response = self.session.put(url, json=data, headers=req_headers, timeout=30)
            elif method.upper() == "DELETE":
                response = self.session.delete(url, headers=req_headers, timeout=30)
            else:
                raise ValueError(f"Unsupported method: {method}")
                
            return response
        except requests.exceptions.RequestException as e:
            print(f"Request failed: {e}")
            raise

    def test_health_check(self):
        """Test basic health endpoints"""
        print("\n=== HEALTH CHECK TESTS ===")
        
        # Test root endpoint
        try:
            response = self.make_request("GET", "/")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Root endpoint", True, f"API responding: {data.get('message', 'OK')}")
            else:
                self.log_result("Root endpoint", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Root endpoint", False, f"Error: {str(e)}")

        # Test health endpoint
        try:
            response = self.make_request("GET", "/health")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Health check", True, f"Status: {data.get('status', 'OK')}")
            else:
                self.log_result("Health check", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Health check", False, f"Error: {str(e)}")

    def test_auth_endpoints(self):
        """Test authentication endpoints"""
        print("\n=== AUTHENTICATION TESTS ===")
        
        # Test user registration (create test user if not exists)
        try:
            response = self.make_request("POST", "/auth/register", self.test_user)
            if response.status_code == 200:
                data = response.json()
                self.log_result("User registration", True, "Test user registered successfully")
            elif response.status_code == 400 and "already" in response.text.lower():
                self.log_result("User registration", True, "Test user already exists (expected)")
            else:
                self.log_result("User registration", False, f"Status: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("User registration", False, f"Error: {str(e)}")

        # Test login with demo user
        try:
            login_data = {"email": self.demo_user["email"], "password": self.demo_user["password"]}
            response = self.make_request("POST", "/auth/login", login_data)
            
            if response.status_code == 200:
                data = response.json()
                self.auth_token = data.get("token")
                self.current_user = data.get("user")
                self.log_result("User login", True, f"Logged in as {self.current_user.get('username', 'unknown')}")
            else:
                # Try registering demo user first
                reg_response = self.make_request("POST", "/auth/register", self.demo_user)
                if reg_response.status_code == 200:
                    # Try login again
                    response = self.make_request("POST", "/auth/login", login_data)
                    if response.status_code == 200:
                        data = response.json()
                        self.auth_token = data.get("token")
                        self.current_user = data.get("user")
                        self.log_result("User login", True, f"Registered and logged in as {self.current_user.get('username', 'unknown')}")
                    else:
                        self.log_result("User login", False, f"Login failed after registration: {response.status_code}")
                else:
                    self.log_result("User login", False, f"Login failed: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("User login", False, f"Error: {str(e)}")

        # Test get current user
        if self.auth_token:
            try:
                response = self.make_request("GET", "/auth/me")
                if response.status_code == 200:
                    data = response.json()
                    self.log_result("Get current user", True, f"Retrieved user: {data.get('username', 'unknown')}")
                else:
                    self.log_result("Get current user", False, f"Status: {response.status_code}")
            except Exception as e:
                self.log_result("Get current user", False, f"Error: {str(e)}")

    def test_post_endpoints(self):
        """Test post-related endpoints"""
        print("\n=== POST TESTS ===")
        
        if not self.auth_token:
            self.log_result("Post tests", False, "No auth token available")
            return

        post_id = None
        
        # Test create post
        try:
            post_data = {
                "content": "This is a test post from the API testing suite! 🔥",
                "location": "Test Location"
            }
            response = self.make_request("POST", "/posts", post_data)
            if response.status_code == 200:
                data = response.json()
                post_id = data.get("id")
                self.log_result("Create post", True, f"Post created with ID: {post_id}")
            else:
                self.log_result("Create post", False, f"Status: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("Create post", False, f"Error: {str(e)}")

        # Test get all posts
        try:
            response = self.make_request("GET", "/posts")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get all posts", True, f"Retrieved {len(data)} posts")
            else:
                self.log_result("Get all posts", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get all posts", False, f"Error: {str(e)}")

        # Test get feed
        try:
            response = self.make_request("GET", "/posts/feed")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get feed", True, f"Retrieved {len(data)} feed posts")
            else:
                self.log_result("Get feed", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get feed", False, f"Error: {str(e)}")

        # Test get single post
        if post_id:
            try:
                response = self.make_request("GET", f"/posts/{post_id}")
                if response.status_code == 200:
                    data = response.json()
                    self.log_result("Get single post", True, f"Retrieved post: {data.get('content', '')[:50]}...")
                else:
                    self.log_result("Get single post", False, f"Status: {response.status_code}")
            except Exception as e:
                self.log_result("Get single post", False, f"Error: {str(e)}")

            # Test like post
            try:
                response = self.make_request("POST", f"/posts/{post_id}/like")
                if response.status_code == 200:
                    data = response.json()
                    self.log_result("Like post", True, f"Post liked: {data.get('liked', False)}")
                else:
                    self.log_result("Like post", False, f"Status: {response.status_code}")
            except Exception as e:
                self.log_result("Like post", False, f"Error: {str(e)}")

        return post_id

    def test_comment_endpoints(self, post_id: str = None):
        """Test comment-related endpoints"""
        print("\n=== COMMENT TESTS ===")
        
        if not self.auth_token:
            self.log_result("Comment tests", False, "No auth token available")
            return

        if not post_id:
            self.log_result("Comment tests", False, "No post ID available for testing")
            return

        # Test create comment
        try:
            comment_data = {"content": "This is a test comment! Great post! 👍"}
            response = self.make_request("POST", f"/posts/{post_id}/comments", comment_data)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Create comment", True, f"Comment created: {data.get('content', '')[:30]}...")
            else:
                self.log_result("Create comment", False, f"Status: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("Create comment", False, f"Error: {str(e)}")

        # Test get comments
        try:
            response = self.make_request("GET", f"/posts/{post_id}/comments")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get comments", True, f"Retrieved {len(data)} comments")
            else:
                self.log_result("Get comments", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get comments", False, f"Error: {str(e)}")

    def test_user_endpoints(self):
        """Test user-related endpoints"""
        print("\n=== USER TESTS ===")
        
        if not self.auth_token:
            self.log_result("User tests", False, "No auth token available")
            return

        # Test update profile
        try:
            update_data = {
                "bio": "Updated bio from API test",
                "location": "Test City"
            }
            response = self.make_request("PUT", "/users/me", update_data)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Update profile", True, f"Profile updated: {data.get('bio', '')}")
            else:
                self.log_result("Update profile", False, f"Status: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("Update profile", False, f"Error: {str(e)}")

        # Test get user profile
        if self.current_user:
            try:
                user_id = self.current_user.get("id")
                response = self.make_request("GET", f"/users/{user_id}")
                if response.status_code == 200:
                    data = response.json()
                    self.log_result("Get user profile", True, f"Retrieved profile for: {data.get('username', 'unknown')}")
                else:
                    self.log_result("Get user profile", False, f"Status: {response.status_code}")
            except Exception as e:
                self.log_result("Get user profile", False, f"Error: {str(e)}")

        # Test search users
        try:
            response = self.make_request("GET", "/users/search/demo")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Search users", True, f"Found {len(data)} users matching 'demo'")
            else:
                self.log_result("Search users", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Search users", False, f"Error: {str(e)}")

    def test_status_endpoints(self):
        """Test status-related endpoints"""
        print("\n=== STATUS TESTS ===")
        
        if not self.auth_token:
            self.log_result("Status tests", False, "No auth token available")
            return

        # Test create status
        try:
            status_data = {
                "content": "Test status from API! 🔥",
                "background_color": "#ff6b6b"
            }
            response = self.make_request("POST", "/statuses", status_data)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Create status", True, f"Status created: {data.get('content', '')[:30]}...")
            else:
                self.log_result("Create status", False, f"Status: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("Create status", False, f"Error: {str(e)}")

        # Test get statuses
        try:
            response = self.make_request("GET", "/statuses")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get statuses", True, f"Retrieved {len(data)} status groups")
            else:
                self.log_result("Get statuses", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get statuses", False, f"Error: {str(e)}")

    def test_message_endpoints(self):
        """Test message-related endpoints"""
        print("\n=== MESSAGE TESTS ===")
        
        if not self.auth_token:
            self.log_result("Message tests", False, "No auth token available")
            return

        # Test get conversations
        try:
            response = self.make_request("GET", "/conversations")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get conversations", True, f"Retrieved {len(data)} conversations")
            else:
                self.log_result("Get conversations", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get conversations", False, f"Error: {str(e)}")

        # Note: Testing send message requires another user ID, which we might not have
        # This is a limitation of the test setup

    def test_notification_endpoints(self):
        """Test notification-related endpoints"""
        print("\n=== NOTIFICATION TESTS ===")
        
        if not self.auth_token:
            self.log_result("Notification tests", False, "No auth token available")
            return

        # Test get notifications
        try:
            response = self.make_request("GET", "/notifications")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get notifications", True, f"Retrieved {len(data)} notifications")
            else:
                self.log_result("Get notifications", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get notifications", False, f"Error: {str(e)}")

        # Test get unread count
        try:
            response = self.make_request("GET", "/notifications/unread-count")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get unread count", True, f"Unread count: {data.get('count', 0)}")
            else:
                self.log_result("Get unread count", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get unread count", False, f"Error: {str(e)}")

        # Test mark notifications as read
        try:
            response = self.make_request("POST", "/notifications/mark-read")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Mark notifications read", True, f"Success: {data.get('success', False)}")
            else:
                self.log_result("Mark notifications read", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Mark notifications read", False, f"Error: {str(e)}")

    def test_place_endpoints(self):
        """Test place-related endpoints"""
        print("\n=== PLACE TESTS ===")
        
        if not self.auth_token:
            self.log_result("Place tests", False, "No auth token available")
            return

        place_id = None

        # Test create place
        try:
            place_data = {
                "name": "Test Cafe",
                "description": "A great place for testing APIs",
                "address": "123 Test Street, Test City",
                "latitude": 40.7128,
                "longitude": -74.0060,
                "category": "cafe",
                "rating": 4.5
            }
            response = self.make_request("POST", "/places", place_data)
            if response.status_code == 200:
                data = response.json()
                place_id = data.get("id")
                self.log_result("Create place", True, f"Place created: {data.get('name', 'Unknown')}")
            else:
                self.log_result("Create place", False, f"Status: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("Create place", False, f"Error: {str(e)}")

        # Test get places
        try:
            response = self.make_request("GET", "/places")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get places", True, f"Retrieved {len(data)} places")
            else:
                self.log_result("Get places", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get places", False, f"Error: {str(e)}")

        # Test get single place
        if place_id:
            try:
                response = self.make_request("GET", f"/places/{place_id}")
                if response.status_code == 200:
                    data = response.json()
                    self.log_result("Get single place", True, f"Retrieved place: {data.get('name', 'Unknown')}")
                else:
                    self.log_result("Get single place", False, f"Status: {response.status_code}")
            except Exception as e:
                self.log_result("Get single place", False, f"Error: {str(e)}")

    def test_discover_endpoints(self):
        """Test discover-related endpoints"""
        print("\n=== DISCOVER TESTS ===")
        
        if not self.auth_token:
            self.log_result("Discover tests", False, "No auth token available")
            return

        # Test trending posts
        try:
            response = self.make_request("GET", "/discover/trending")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get trending", True, f"Retrieved {len(data)} trending posts")
            else:
                self.log_result("Get trending", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get trending", False, f"Error: {str(e)}")

        # Test search
        try:
            response = self.make_request("GET", "/discover/search?query=test")
            if response.status_code == 200:
                data = response.json()
                posts_count = len(data.get("posts", []))
                users_count = len(data.get("users", []))
                places_count = len(data.get("places", []))
                self.log_result("Search content", True, f"Found {posts_count} posts, {users_count} users, {places_count} places")
            else:
                self.log_result("Search content", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Search content", False, f"Error: {str(e)}")

        # Test suggested users
        try:
            response = self.make_request("GET", "/discover/suggested-users")
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get suggested users", True, f"Retrieved {len(data)} suggested users")
            else:
                self.log_result("Get suggested users", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get suggested users", False, f"Error: {str(e)}")

    def run_all_tests(self):
        """Run all test suites"""
        print("🔥 Starting Flames-Up API Tests 🔥")
        print(f"Testing against: {self.base_url}")
        print("=" * 60)
        
        # Run tests in order
        self.test_health_check()
        self.test_auth_endpoints()
        
        if self.auth_token:
            post_id = self.test_post_endpoints()
            self.test_comment_endpoints(post_id)
            self.test_user_endpoints()
            self.test_status_endpoints()
            self.test_message_endpoints()
            self.test_notification_endpoints()
            self.test_place_endpoints()
            self.test_discover_endpoints()
        else:
            print("\n❌ Authentication failed - skipping authenticated endpoint tests")

        # Print summary
        self.print_summary()

    def print_summary(self):
        """Print test results summary"""
        print("\n" + "=" * 60)
        print("🔥 TEST RESULTS SUMMARY 🔥")
        print("=" * 60)
        
        total_tests = len(self.test_results)
        passed_tests = sum(1 for r in self.test_results if r["success"])
        failed_tests = total_tests - passed_tests
        
        print(f"Total Tests: {total_tests}")
        print(f"✅ Passed: {passed_tests}")
        print(f"❌ Failed: {failed_tests}")
        print(f"Success Rate: {(passed_tests/total_tests*100):.1f}%" if total_tests > 0 else "0%")
        
        if failed_tests > 0:
            print("\n❌ FAILED TESTS:")
            for result in self.test_results:
                if not result["success"]:
                    print(f"  - {result['test']}: {result['details']}")
        
        print("\n" + "=" * 60)

if __name__ == "__main__":
    # Run the tests
    tester = FlamesUpAPITester()
    tester.run_all_tests()