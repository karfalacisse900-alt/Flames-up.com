#!/usr/bin/env python3
"""
Comprehensive Backend API Testing for Flames-Up Check-In Post Feature
Tests the new Check-In Post functionality including proximity verification,
post creation with different types, nearby feed, and post deletion.
"""

import requests
import json
import sys
from typing import Dict, Any, Optional

# Configuration
BASE_URL = "https://flames-up-preview.preview.emergentagent.com/api"
TEST_EMAIL = "demo@flames-up.com"
TEST_PASSWORD = "demo123456"

class FlamesUpTester:
    def __init__(self):
        self.base_url = BASE_URL
        self.token = None
        self.user_id = None
        self.created_posts = []  # Track created posts for cleanup
        
    def log(self, message: str, level: str = "INFO"):
        """Log test messages"""
        print(f"[{level}] {message}")
        
    def make_request(self, method: str, endpoint: str, data: Optional[Dict] = None, 
                    headers: Optional[Dict] = None, params: Optional[Dict] = None) -> Dict[str, Any]:
        """Make HTTP request with error handling"""
        url = f"{self.base_url}{endpoint}"
        
        # Add auth header if token exists
        if self.token and headers is None:
            headers = {"Authorization": f"Bearer {self.token}"}
        elif self.token and headers:
            headers["Authorization"] = f"Bearer {self.token}"
            
        try:
            if method.upper() == "GET":
                response = requests.get(url, headers=headers, params=params, timeout=30)
            elif method.upper() == "POST":
                response = requests.post(url, json=data, headers=headers, timeout=30)
            elif method.upper() == "DELETE":
                response = requests.delete(url, headers=headers, timeout=30)
            else:
                raise ValueError(f"Unsupported method: {method}")
                
            self.log(f"{method} {endpoint} -> {response.status_code}")
            
            if response.status_code >= 400:
                self.log(f"Error response: {response.text}", "ERROR")
                
            return {
                "status_code": response.status_code,
                "data": response.json() if response.content else {},
                "success": 200 <= response.status_code < 300
            }
            
        except requests.exceptions.RequestException as e:
            self.log(f"Request failed: {str(e)}", "ERROR")
            return {"status_code": 0, "data": {}, "success": False, "error": str(e)}
        except json.JSONDecodeError as e:
            self.log(f"JSON decode error: {str(e)}", "ERROR")
            return {"status_code": response.status_code, "data": {}, "success": False, "error": "Invalid JSON"}

    def test_login(self) -> bool:
        """Test user login and get authentication token"""
        self.log("Testing login...")
        
        result = self.make_request("POST", "/auth/login", {
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD
        })
        
        if result["success"] and "token" in result["data"]:
            self.token = result["data"]["token"]
            self.user_id = result["data"]["user"]["id"]
            self.log(f"✅ Login successful. User ID: {self.user_id}")
            return True
        else:
            self.log(f"❌ Login failed: {result.get('data', {})}", "ERROR")
            return False

    def test_proximity_verification(self) -> bool:
        """Test proximity verification endpoint"""
        self.log("Testing proximity verification...")
        
        # Test NEAR scenario (within 200m)
        near_data = {
            "user_lat": 40.7128,
            "user_lng": -74.006,
            "place_lat": 40.7130,  # Very close coordinates
            "place_lng": -74.006
        }
        
        result = self.make_request("POST", "/places/verify-proximity", near_data)
        
        if not result["success"]:
            self.log(f"❌ Proximity verification (near) failed: {result.get('data', {})}", "ERROR")
            return False
            
        near_response = result["data"]
        if not near_response.get("is_near", False):
            self.log(f"❌ Near proximity check failed. Expected is_near=true, got: {near_response}", "ERROR")
            return False
            
        self.log(f"✅ Near proximity check passed: {near_response}")
        
        # Test FAR scenario (>200m)
        far_data = {
            "user_lat": 40.7128,
            "user_lng": -74.006,
            "place_lat": 40.8000,  # Much farther coordinates
            "place_lng": -74.006
        }
        
        result = self.make_request("POST", "/places/verify-proximity", far_data)
        
        if not result["success"]:
            self.log(f"❌ Proximity verification (far) failed: {result.get('data', {})}", "ERROR")
            return False
            
        far_response = result["data"]
        if far_response.get("is_near", True):  # Should be False
            self.log(f"❌ Far proximity check failed. Expected is_near=false, got: {far_response}", "ERROR")
            return False
            
        self.log(f"✅ Far proximity check passed: {far_response}")
        return True

    def test_create_checkin_post(self) -> Optional[str]:
        """Test creating a check-in post"""
        self.log("Testing check-in post creation...")
        
        checkin_data = {
            "content": "Testing at KFC! Amazing fried chicken here 🍗",
            "post_type": "check_in",
            "place_id": "test_place_123",
            "place_name": "KFC Times Square",
            "place_lat": 40.7580,
            "place_lng": -73.9855
        }
        
        result = self.make_request("POST", "/posts", checkin_data)
        
        if not result["success"]:
            self.log(f"❌ Check-in post creation failed: {result.get('data', {})}", "ERROR")
            return None
            
        post = result["data"]
        post_id = post.get("id")
        
        # Verify required fields
        required_fields = ["post_type", "place_name", "is_verified_checkin"]
        missing_fields = [field for field in required_fields if field not in post]
        
        if missing_fields:
            self.log(f"❌ Check-in post missing fields: {missing_fields}", "ERROR")
            return None
            
        if post["post_type"] != "check_in":
            self.log(f"❌ Check-in post has wrong type: {post['post_type']}", "ERROR")
            return None
            
        if not post.get("is_verified_checkin", False):
            self.log(f"❌ Check-in post not marked as verified: {post.get('is_verified_checkin')}", "ERROR")
            return None
            
        self.log(f"✅ Check-in post created successfully: {post_id}")
        self.created_posts.append(post_id)
        return post_id

    def test_create_question_post(self) -> Optional[str]:
        """Test creating a question post"""
        self.log("Testing question post creation...")
        
        question_data = {
            "content": "Best pizza place in the Bronx? Looking for authentic NY style! 🍕",
            "post_type": "question"
        }
        
        result = self.make_request("POST", "/posts", question_data)
        
        if not result["success"]:
            self.log(f"❌ Question post creation failed: {result.get('data', {})}", "ERROR")
            return None
            
        post = result["data"]
        post_id = post.get("id")
        
        if post.get("post_type") != "question":
            self.log(f"❌ Question post has wrong type: {post.get('post_type')}", "ERROR")
            return None
            
        self.log(f"✅ Question post created successfully: {post_id}")
        self.created_posts.append(post_id)
        return post_id

    def test_nearby_feed(self) -> bool:
        """Test nearby feed endpoint"""
        self.log("Testing nearby feed...")
        
        params = {
            "lat": 40.7128,
            "lng": -74.006
        }
        
        result = self.make_request("GET", "/posts/nearby-feed", params=params)
        
        if not result["success"]:
            self.log(f"❌ Nearby feed failed: {result.get('data', {})}", "ERROR")
            return False
            
        posts = result["data"]
        if not isinstance(posts, list):
            self.log(f"❌ Nearby feed should return array, got: {type(posts)}", "ERROR")
            return False
            
        self.log(f"✅ Nearby feed returned {len(posts)} posts")
        
        # Check if any posts have distance_km field (for nearby check-ins)
        nearby_checkins = [p for p in posts if "distance_km" in p]
        if nearby_checkins:
            self.log(f"✅ Found {len(nearby_checkins)} nearby check-in posts with distance info")
            
        return True

    def test_delete_post(self, post_id: str) -> bool:
        """Test deleting a post"""
        self.log(f"Testing post deletion for post: {post_id}")
        
        result = self.make_request("DELETE", f"/posts/{post_id}")
        
        if not result["success"]:
            self.log(f"❌ Post deletion failed: {result.get('data', {})}", "ERROR")
            return False
            
        response = result["data"]
        if not response.get("deleted", False):
            self.log(f"❌ Post deletion response invalid: {response}", "ERROR")
            return False
            
        self.log(f"✅ Post {post_id} deleted successfully")
        return True

    def test_existing_endpoints(self) -> bool:
        """Test that existing endpoints still work"""
        self.log("Testing existing endpoints...")
        
        # Test feed endpoint
        result = self.make_request("GET", "/posts/feed")
        if not result["success"]:
            self.log(f"❌ Posts feed endpoint failed: {result.get('data', {})}", "ERROR")
            return False
        self.log("✅ Posts feed endpoint working")
        
        # Test statuses endpoint
        result = self.make_request("GET", "/statuses")
        if not result["success"]:
            self.log(f"❌ Statuses endpoint failed: {result.get('data', {})}", "ERROR")
            return False
        self.log("✅ Statuses endpoint working")
        
        return True

    def cleanup_posts(self):
        """Clean up created posts"""
        self.log("Cleaning up created posts...")
        for post_id in self.created_posts:
            self.test_delete_post(post_id)

    def run_all_tests(self) -> bool:
        """Run all tests in sequence"""
        self.log("=" * 60)
        self.log("STARTING FLAMES-UP CHECK-IN POST FEATURE TESTS")
        self.log("=" * 60)
        
        # Step 1: Login
        if not self.test_login():
            self.log("❌ Cannot proceed without authentication", "ERROR")
            return False
            
        # Step 2: Test proximity verification
        if not self.test_proximity_verification():
            self.log("❌ Proximity verification tests failed", "ERROR")
            return False
            
        # Step 3: Test check-in post creation
        checkin_post_id = self.test_create_checkin_post()
        if not checkin_post_id:
            self.log("❌ Check-in post creation failed", "ERROR")
            return False
            
        # Step 4: Test question post creation
        question_post_id = self.test_create_question_post()
        if not question_post_id:
            self.log("❌ Question post creation failed", "ERROR")
            return False
            
        # Step 5: Test nearby feed
        if not self.test_nearby_feed():
            self.log("❌ Nearby feed tests failed", "ERROR")
            return False
            
        # Step 6: Test existing endpoints
        if not self.test_existing_endpoints():
            self.log("❌ Existing endpoints tests failed", "ERROR")
            return False
            
        # Step 7: Test post deletion
        if not self.test_delete_post(checkin_post_id):
            self.log("❌ Post deletion test failed", "ERROR")
            return False
            
        # Keep question post for now, delete in cleanup
        
        self.log("=" * 60)
        self.log("✅ ALL CHECK-IN POST FEATURE TESTS PASSED!")
        self.log("=" * 60)
        
        return True

def main():
    """Main test execution"""
    tester = FlamesUpTester()
    
    try:
        success = tester.run_all_tests()
        if success:
            print("\n🎉 All tests completed successfully!")
            sys.exit(0)
        else:
            print("\n💥 Some tests failed!")
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n⚠️ Tests interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n💥 Unexpected error: {str(e)}")
        sys.exit(1)
    finally:
        # Cleanup
        tester.cleanup_posts()

if __name__ == "__main__":
    main()