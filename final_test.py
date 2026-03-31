#!/usr/bin/env python3
"""
Final comprehensive test for follow functionality and message system
"""

import requests
import json
from datetime import datetime

class FlamesUpFinalTester:
    def __init__(self, base_url: str = "https://flames-up-preview.preview.emergentagent.com/api"):
        self.base_url = base_url
        self.session = requests.Session()
        self.demo_token = None
        self.test_token = None
        self.demo_user = None
        self.test_user = None
        self.test_results = []

    def log_result(self, test_name: str, success: bool, details: str = ""):
        """Log test results"""
        result = {
            "test": test_name,
            "success": success,
            "details": details,
            "timestamp": datetime.now().isoformat()
        }
        self.test_results.append(result)
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} {test_name}: {details}")

    def make_request(self, method: str, endpoint: str, data: dict = None, token: str = None) -> requests.Response:
        """Make HTTP request"""
        url = f"{self.base_url}{endpoint}"
        headers = {"Content-Type": "application/json"}
        
        if token:
            headers["Authorization"] = f"Bearer {token}"
            
        try:
            if method.upper() == "GET":
                response = self.session.get(url, headers=headers, timeout=30)
            elif method.upper() == "POST":
                response = self.session.post(url, json=data, headers=headers, timeout=30)
            elif method.upper() == "PUT":
                response = self.session.put(url, json=data, headers=headers, timeout=30)
            elif method.upper() == "DELETE":
                response = self.session.delete(url, headers=headers, timeout=30)
            else:
                raise ValueError(f"Unsupported method: {method}")
                
            return response
        except requests.exceptions.RequestException as e:
            print(f"Request failed: {e}")
            raise

    def setup_users(self):
        """Setup two users for testing interactions"""
        print("\n=== SETTING UP TEST USERS ===")
        
        # Login as demo user
        try:
            login_data = {"email": "demo@flames-up.com", "password": "demo123456"}
            response = self.make_request("POST", "/auth/login", login_data)
            if response.status_code == 200:
                data = response.json()
                self.demo_token = data.get("token")
                self.demo_user = data.get("user")
                self.log_result("Demo user login", True, f"Logged in as {self.demo_user.get('username')}")
            else:
                self.log_result("Demo user login", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Demo user login", False, f"Error: {str(e)}")

        # Login as test user
        try:
            login_data = {"email": "test@flames-up.com", "password": "test123456"}
            response = self.make_request("POST", "/auth/login", login_data)
            if response.status_code == 200:
                data = response.json()
                self.test_token = data.get("token")
                self.test_user = data.get("user")
                self.log_result("Test user login", True, f"Logged in as {self.test_user.get('username')}")
            else:
                self.log_result("Test user login", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Test user login", False, f"Error: {str(e)}")

    def test_follow_functionality(self):
        """Test follow/unfollow functionality between users"""
        print("\n=== FOLLOW FUNCTIONALITY TESTS ===")
        
        if not self.demo_token or not self.test_token or not self.demo_user or not self.test_user:
            self.log_result("Follow tests", False, "Missing user tokens or data")
            return

        # Demo user follows test user
        try:
            response = self.make_request("POST", f"/users/{self.test_user['id']}/follow", token=self.demo_token)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Follow user", True, f"Following status: {data.get('following', False)}")
            else:
                self.log_result("Follow user", False, f"Status: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("Follow user", False, f"Error: {str(e)}")

        # Check if follow relationship exists
        try:
            response = self.make_request("GET", f"/users/{self.test_user['id']}", token=self.demo_token)
            if response.status_code == 200:
                data = response.json()
                is_following = data.get("is_following", False)
                self.log_result("Check follow status", True, f"Is following: {is_following}")
            else:
                self.log_result("Check follow status", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Check follow status", False, f"Error: {str(e)}")

        # Test unfollow (follow again to toggle)
        try:
            response = self.make_request("POST", f"/users/{self.test_user['id']}/follow", token=self.demo_token)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Unfollow user", True, f"Following status after toggle: {data.get('following', False)}")
            else:
                self.log_result("Unfollow user", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Unfollow user", False, f"Error: {str(e)}")

    def test_message_system(self):
        """Test messaging between users"""
        print("\n=== MESSAGE SYSTEM TESTS ===")
        
        if not self.demo_token or not self.test_token or not self.demo_user or not self.test_user:
            self.log_result("Message tests", False, "Missing user tokens or data")
            return

        # Demo user sends message to test user
        try:
            message_data = {
                "receiver_id": self.test_user["id"],
                "content": "Hello from demo user! This is a test message."
            }
            response = self.make_request("POST", "/messages", message_data, token=self.demo_token)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Send message", True, f"Message sent: {data.get('content', '')[:30]}...")
            else:
                self.log_result("Send message", False, f"Status: {response.status_code}, Response: {response.text}")
        except Exception as e:
            self.log_result("Send message", False, f"Error: {str(e)}")

        # Test user checks conversations
        try:
            response = self.make_request("GET", "/conversations", token=self.test_token)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get conversations (receiver)", True, f"Found {len(data)} conversations")
            else:
                self.log_result("Get conversations (receiver)", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get conversations (receiver)", False, f"Error: {str(e)}")

        # Test user gets messages with demo user
        try:
            response = self.make_request("GET", f"/messages/{self.demo_user['id']}", token=self.test_token)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get messages", True, f"Retrieved {len(data)} messages")
            else:
                self.log_result("Get messages", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get messages", False, f"Error: {str(e)}")

        # Test user replies
        try:
            reply_data = {
                "receiver_id": self.demo_user["id"],
                "content": "Hello back! This is a reply from test user."
            }
            response = self.make_request("POST", "/messages", reply_data, token=self.test_token)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Send reply", True, f"Reply sent: {data.get('content', '')[:30]}...")
            else:
                self.log_result("Send reply", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Send reply", False, f"Error: {str(e)}")

    def test_additional_endpoints(self):
        """Test some additional endpoints that might not have been fully tested"""
        print("\n=== ADDITIONAL ENDPOINT TESTS ===")
        
        if not self.demo_token:
            self.log_result("Additional tests", False, "Missing demo token")
            return

        # Test get user posts
        try:
            response = self.make_request("GET", f"/users/{self.demo_user['id']}/posts", token=self.demo_token)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get user posts", True, f"Retrieved {len(data)} user posts")
            else:
                self.log_result("Get user posts", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get user posts", False, f"Error: {str(e)}")

        # Test nearby places (with sample coordinates)
        try:
            response = self.make_request("GET", "/places/nearby?latitude=40.7128&longitude=-74.0060&radius=10", token=self.demo_token)
            if response.status_code == 200:
                data = response.json()
                self.log_result("Get nearby places", True, f"Found {len(data)} nearby places")
            else:
                self.log_result("Get nearby places", False, f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Get nearby places", False, f"Error: {str(e)}")

        # Test status view functionality (if we have a status)
        try:
            # First get statuses to find one to view
            response = self.make_request("GET", "/statuses", token=self.demo_token)
            if response.status_code == 200:
                data = response.json()
                if data and len(data) > 0 and data[0].get("statuses"):
                    status_id = data[0]["statuses"][0]["id"]
                    # Now view the status
                    view_response = self.make_request("POST", f"/statuses/{status_id}/view", token=self.demo_token)
                    if view_response.status_code == 200:
                        self.log_result("View status", True, "Status viewed successfully")
                    else:
                        self.log_result("View status", False, f"Status: {view_response.status_code}")
                else:
                    self.log_result("View status", True, "No statuses available to view (expected)")
            else:
                self.log_result("View status", False, f"Failed to get statuses: {response.status_code}")
        except Exception as e:
            self.log_result("View status", False, f"Error: {str(e)}")

    def run_final_tests(self):
        """Run all final tests"""
        print("🔥 Starting Flames-Up API Final Tests 🔥")
        print(f"Testing against: {self.base_url}")
        print("=" * 60)
        
        self.setup_users()
        
        if self.demo_token and self.test_token:
            self.test_follow_functionality()
            self.test_message_system()
            self.test_additional_endpoints()
        else:
            print("\n❌ User setup failed - skipping interaction tests")

        # Print summary
        self.print_summary()

    def print_summary(self):
        """Print test results summary"""
        print("\n" + "=" * 60)
        print("🔥 FINAL TEST RESULTS SUMMARY 🔥")
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
    # Run the final tests
    tester = FlamesUpFinalTester()
    tester.run_final_tests()