#!/usr/bin/env python3
"""
Additional Edge Case Tests for Flames-Up API
Tests error handling and edge cases
"""

import requests
import json
from datetime import datetime

class FlamesUpEdgeCaseTester:
    def __init__(self, base_url: str = "https://flames-up-preview.preview.emergentagent.com/api"):
        self.base_url = base_url
        self.session = requests.Session()
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

    def make_request(self, method: str, endpoint: str, data: dict = None, headers: dict = None) -> requests.Response:
        """Make HTTP request"""
        url = f"{self.base_url}{endpoint}"
        req_headers = {"Content-Type": "application/json"}
        
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

    def test_error_handling(self):
        """Test error handling scenarios"""
        print("\n=== ERROR HANDLING TESTS ===")
        
        # Test invalid login
        try:
            invalid_login = {"email": "invalid@test.com", "password": "wrongpassword"}
            response = self.make_request("POST", "/auth/login", invalid_login)
            if response.status_code == 401:
                self.log_result("Invalid login handling", True, "Correctly returns 401 for invalid credentials")
            else:
                self.log_result("Invalid login handling", False, f"Expected 401, got {response.status_code}")
        except Exception as e:
            self.log_result("Invalid login handling", False, f"Error: {str(e)}")

        # Test unauthorized access
        try:
            response = self.make_request("GET", "/auth/me")
            if response.status_code == 403:
                self.log_result("Unauthorized access handling", True, "Correctly returns 403 for missing auth")
            else:
                self.log_result("Unauthorized access handling", False, f"Expected 403, got {response.status_code}")
        except Exception as e:
            self.log_result("Unauthorized access handling", False, f"Error: {str(e)}")

        # Test invalid token
        try:
            headers = {"Authorization": "Bearer invalid_token_here"}
            response = self.make_request("GET", "/auth/me", headers=headers)
            if response.status_code == 401:
                self.log_result("Invalid token handling", True, "Correctly returns 401 for invalid token")
            else:
                self.log_result("Invalid token handling", False, f"Expected 401, got {response.status_code}")
        except Exception as e:
            self.log_result("Invalid token handling", False, f"Error: {str(e)}")

        # Test non-existent post
        try:
            fake_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0IiwiZXhwIjo5OTk5OTk5OTk5fQ.invalid"
            headers = {"Authorization": f"Bearer {fake_token}"}
            response = self.make_request("GET", "/posts/non-existent-id", headers=headers)
            if response.status_code in [401, 404]:
                self.log_result("Non-existent post handling", True, f"Correctly returns {response.status_code}")
            else:
                self.log_result("Non-existent post handling", False, f"Unexpected status: {response.status_code}")
        except Exception as e:
            self.log_result("Non-existent post handling", False, f"Error: {str(e)}")

    def test_data_validation(self):
        """Test data validation"""
        print("\n=== DATA VALIDATION TESTS ===")
        
        # Test registration with invalid email
        try:
            invalid_user = {
                "email": "not-an-email",
                "password": "test123",
                "username": "testuser",
                "full_name": "Test User"
            }
            response = self.make_request("POST", "/auth/register", invalid_user)
            if response.status_code == 422:  # Validation error
                self.log_result("Invalid email validation", True, "Correctly rejects invalid email format")
            else:
                self.log_result("Invalid email validation", False, f"Expected 422, got {response.status_code}")
        except Exception as e:
            self.log_result("Invalid email validation", False, f"Error: {str(e)}")

        # Test registration with missing fields
        try:
            incomplete_user = {
                "email": "test@example.com",
                "password": "test123"
                # Missing username and full_name
            }
            response = self.make_request("POST", "/auth/register", incomplete_user)
            if response.status_code == 422:  # Validation error
                self.log_result("Missing fields validation", True, "Correctly rejects incomplete registration data")
            else:
                self.log_result("Missing fields validation", False, f"Expected 422, got {response.status_code}")
        except Exception as e:
            self.log_result("Missing fields validation", False, f"Error: {str(e)}")

    def test_cors_headers(self):
        """Test CORS headers"""
        print("\n=== CORS TESTS ===")
        
        try:
            response = self.make_request("GET", "/")
            cors_headers = [
                "access-control-allow-origin",
                "access-control-allow-methods",
                "access-control-allow-headers"
            ]
            
            has_cors = any(header.lower() in [h.lower() for h in response.headers.keys()] for header in cors_headers)
            
            if has_cors:
                self.log_result("CORS headers", True, "CORS headers present in response")
            else:
                self.log_result("CORS headers", False, "CORS headers missing")
        except Exception as e:
            self.log_result("CORS headers", False, f"Error: {str(e)}")

    def run_edge_case_tests(self):
        """Run all edge case tests"""
        print("🔥 Starting Flames-Up API Edge Case Tests 🔥")
        print(f"Testing against: {self.base_url}")
        print("=" * 60)
        
        self.test_error_handling()
        self.test_data_validation()
        self.test_cors_headers()
        
        # Print summary
        self.print_summary()

    def print_summary(self):
        """Print test results summary"""
        print("\n" + "=" * 60)
        print("🔥 EDGE CASE TEST RESULTS SUMMARY 🔥")
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
    # Run the edge case tests
    tester = FlamesUpEdgeCaseTester()
    tester.run_edge_case_tests()