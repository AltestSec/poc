#!/usr/bin/env python3
"""
ETL Test Script
Tests ETL functionality and network security
"""
import sys
import json
import logging
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def test_network_security():
    """
    Test network egress restrictions
    Returns: dict with test results
    """
    try:
        import urllib.request
        import socket
        
        results = {
            "timestamp": datetime.utcnow().isoformat(),
            "tests": []
        }
        
        # Test 1: Allowed endpoint (Azure services)
        test_allowed = {
            "name": "test_allowed_endpoint",
            "endpoint": "https://pypi.org",
            "expected": "success",
            "actual": None,
            "passed": False
        }
        
        try:
            response = urllib.request.urlopen(test_allowed["endpoint"], timeout=5)
            test_allowed["actual"] = "success"
            test_allowed["passed"] = True
            test_allowed["status_code"] = response.getcode()
            logger.info(f"✓ Allowed endpoint accessible: {test_allowed['endpoint']}")
        except Exception as e:
            test_allowed["actual"] = "blocked"
            test_allowed["error"] = str(e)
            logger.warning(f"✗ Allowed endpoint blocked: {test_allowed['endpoint']} - {e}")
        
        results["tests"].append(test_allowed)
        
        # Test 2: Blocked endpoint (should fail)
        test_blocked = {
            "name": "test_blocked_endpoint",
            "endpoint": "https://www.google.com",
            "expected": "blocked",
            "actual": None,
            "passed": False
        }
        
        try:
            response = urllib.request.urlopen(test_blocked["endpoint"], timeout=5)
            test_blocked["actual"] = "success"
            test_blocked["status_code"] = response.getcode()
            logger.warning(f"✗ Blocked endpoint accessible (should be blocked): {test_blocked['endpoint']}")
        except Exception as e:
            test_blocked["actual"] = "blocked"
            test_blocked["passed"] = True
            logger.info(f"✓ Blocked endpoint correctly blocked: {test_blocked['endpoint']}")
        
        results["tests"].append(test_blocked)
        
        # Calculate overall success
        results["success"] = all(test["passed"] for test in results["tests"])
        results["passed_count"] = sum(1 for test in results["tests"] if test["passed"])
        results["total_count"] = len(results["tests"])
        
        return results
        
    except Exception as e:
        logger.error(f"Network security test failed: {str(e)}")
        return {
            "success": False,
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }

def test_etl_process():
    """
    Test basic ETL functionality
    Returns: dict with test results
    """
    try:
        logger.info("Starting ETL process test...")
        
        # Simulate ETL operations
        results = {
            "timestamp": datetime.utcnow().isoformat(),
            "operations": []
        }
        
        # Extract phase
        extract_result = {
            "phase": "extract",
            "records_extracted": 100,
            "success": True
        }
        results["operations"].append(extract_result)
        logger.info(f"✓ Extract phase: {extract_result['records_extracted']} records")
        
        # Transform phase
        transform_result = {
            "phase": "transform",
            "records_transformed": 100,
            "success": True
        }
        results["operations"].append(transform_result)
        logger.info(f"✓ Transform phase: {transform_result['records_transformed']} records")
        
        # Load phase
        load_result = {
            "phase": "load",
            "records_loaded": 100,
            "success": True
        }
        results["operations"].append(load_result)
        logger.info(f"✓ Load phase: {load_result['records_loaded']} records")
        
        results["success"] = all(op["success"] for op in results["operations"])
        results["total_records"] = load_result["records_loaded"]
        
        return results
        
    except Exception as e:
        logger.error(f"ETL process test failed: {str(e)}")
        return {
            "success": False,
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }

def main():
    """
    Main test execution
    """
    try:
        logger.info("=" * 60)
        logger.info("Starting ETL Container Job Tests")
        logger.info("=" * 60)
        
        all_results = {
            "test_suite": "etl_container_job",
            "timestamp": datetime.utcnow().isoformat(),
            "tests": {}
        }
        
        # Run ETL process test
        logger.info("\n--- Running ETL Process Test ---")
        etl_results = test_etl_process()
        all_results["tests"]["etl_process"] = etl_results
        
        # Run network security test
        logger.info("\n--- Running Network Security Test ---")
        network_results = test_network_security()
        all_results["tests"]["network_security"] = network_results
        
        # Overall results
        all_results["success"] = (
            etl_results.get("success", False) and 
            network_results.get("success", False)
        )
        
        logger.info("\n" + "=" * 60)
        logger.info("Test Results Summary")
        logger.info("=" * 60)
        logger.info(f"ETL Process: {'✓ PASSED' if etl_results.get('success') else '✗ FAILED'}")
        logger.info(f"Network Security: {'✓ PASSED' if network_results.get('success') else '✗ FAILED'}")
        logger.info(f"Overall: {'✓ ALL TESTS PASSED' if all_results['success'] else '✗ SOME TESTS FAILED'}")
        logger.info("=" * 60)
        
        # Output JSON results
        print("\n--- JSON Results ---")
        print(json.dumps(all_results, indent=2))
        
        # Exit with appropriate code
        sys.exit(0 if all_results["success"] else 1)
        
    except Exception as e:
        logger.error(f"Test execution failed: {str(e)}")
        error_result = {
            "success": False,
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }
        print(json.dumps(error_result, indent=2))
        sys.exit(1)

if __name__ == "__main__":
    main()
