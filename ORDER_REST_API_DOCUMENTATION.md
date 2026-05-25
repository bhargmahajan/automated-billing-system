# Order REST API Documentation

## Overview
The Order REST API allows external systems to create Order records in Salesforce via HTTP REST calls. The API supports both single order creation and bulk order operations with up to 10,000 orders per request.

## Key Features
- ✅ **Single Order Creation**: Create one order at a time
- ✅ **Bulk Order Creation**: Create up to 10,000 orders in one request
- ✅ **Partial Success Support**: Bulk operations return detailed results for each order
- ✅ **Governor Limit Protection**: Enforces Salesforce DML limits
- ✅ **Comprehensive Validation**: Field-level and business rule validation
- ✅ **Detailed Error Reporting**: Individual error messages for each failed record

## Endpoint Details

### Base URL
```
https://your-instance.salesforce.com/services/apexrest/orders
```

### Authentication
Use OAuth 2.0 authentication with a Connected App. Include the access token in the Authorization header:
```
Authorization: Bearer YOUR_ACCESS_TOKEN
```

## Create Order

### HTTP Method
`POST`

### Endpoint
```
POST /services/apexrest/orders
```

### Headers
```
Content-Type: application/json
Authorization: Bearer YOUR_ACCESS_TOKEN
```

### Request Body

#### Required Fields
| Field | Type | Description |
|-------|------|-------------|
| `AccountId` | String (ID) | Salesforce Account ID (18 characters) |
| `EffectiveDate` | String (Date) | Order effective date in format `YYYY-MM-DD` |
| `Status` | String | Order status - must be either `"Draft"` or `"Activated"` |

#### Optional Fields
| Field | Type | Description |
|-------|------|-------------|
| `External_ID__c` | String | External system order ID for reference |
| `ContractId` | String (ID) | Salesforce Contract ID if order is related to a contract |
| `TotalAmount` | Number | Total order amount (must be non-negative) |
| `Description` | String | Order description or notes |
| `PoNumber` | String | Purchase Order number |
| `PoDate` | String (Date) | Purchase Order date in format `YYYY-MM-DD` |
| `Type` | String | Order type (e.g., "New", "Renewal", "Amendment") |
| `Pricebook2Id` | String (ID) | Pricebook ID for pricing reference |

### Single Order Example

#### Minimal Request
```json
{
  "AccountId": "0015g00000XXXXXX",
  "EffectiveDate": "2026-05-25",
  "Status": "Draft"
}
```

#### Full Request with All Fields
```json
{
  "AccountId": "0015g00000XXXXXX",
  "ContractId": "8005g00000XXXXXX",
  "External_ID__c": "EXT-ORD-12345",
  "EffectiveDate": "2026-05-25",
  "Status": "Draft",
  "TotalAmount": 1500.00,
  "Description": "Q2 2026 Service Order",
  "PoNumber": "PO-2026-067890",
  "PoDate": "2026-05-24",
  "Type": "New",
  "Pricebook2Id": "01s5g00000XXXXXX"
}
```

### Bulk Order Request Example

Create multiple orders in a single request by wrapping them in an `orders` array:

```json
{
  "orders": [
    {
      "AccountId": "0015g00000XXXXXX",
      "EffectiveDate": "2026-05-25",
      "Status": "Draft",
      "External_ID__c": "EXT-ORD-001",
      "TotalAmount": 1000.00
    },
    {
      "AccountId": "0015g00000YYYYYY",
      "EffectiveDate": "2026-05-26",
      "Status": "Draft",
      "External_ID__c": "EXT-ORD-002",
      "TotalAmount": 2000.00
    },
    {
      "AccountId": "0015g00000ZZZZZZ",
      "EffectiveDate": "2026-05-27",
      "Status": "Activated",
      "External_ID__c": "EXT-ORD-003",
      "TotalAmount": 1500.00
    }
  ]
}
```

## Response Formats

### Single Order Response

#### Success Response (HTTP 201)
```json
{
  "success": true,
  "message": "Order created successfully",
  "orderId": "8015g00000XXXXXX",
  "orderNumber": "00000123",
  "errors": []
}
```

#### Validation Error Response (HTTP 400)
```json
{
  "success": false,
  "message": "Validation failed",
  "orderId": null,
  "orderNumber": null,
  "errors": [
    "AccountId is required",
    "EffectiveDate is required"
  ]
}
```

#### Invalid JSON Response (HTTP 400)
```json
{
  "success": false,
  "message": "Invalid JSON format",
  "orderId": null,
  "orderNumber": null,
  "errors": [
    "Unexpected character ('}' (code 125)): was expecting double-quote to start field name..."
  ]
}
```

#### Server Error Response (HTTP 500)
```json
{
  "success": false,
  "message": "Failed to create order",
  "orderId": null,
  "orderNumber": null,
  "errors": [
    "UNABLE_TO_LOCK_ROW: unable to obtain exclusive access to this record"
  ]
}
```

### Bulk Order Response

#### Full Success (HTTP 201)
```json
{
  "success": true,
  "message": "All orders created successfully",
  "totalRecords": 3,
  "successCount": 3,
  "failureCount": 0,
  "results": [
    {
      "success": true,
      "orderId": "8015g00000XXXXXX",
      "orderNumber": "00000123",
      "externalId": "EXT-ORD-001",
      "recordIndex": 0,
      "errors": []
    },
    {
      "success": true,
      "orderId": "8015g00000YYYYYY",
      "orderNumber": "00000124",
      "externalId": "EXT-ORD-002",
      "recordIndex": 1,
      "errors": []
    },
    {
      "success": true,
      "orderId": "8015g00000ZZZZZZ",
      "orderNumber": "00000125",
      "externalId": "EXT-ORD-003",
      "recordIndex": 2,
      "errors": []
    }
  ],
  "errors": []
}
```

#### Partial Success (HTTP 207)
```json
{
  "success": false,
  "message": "Partial success: 2 succeeded, 1 failed",
  "totalRecords": 3,
  "successCount": 2,
  "failureCount": 1,
  "results": [
    {
      "success": true,
      "orderId": "8015g00000XXXXXX",
      "orderNumber": "00000123",
      "externalId": "EXT-ORD-001",
      "recordIndex": 0,
      "errors": []
    },
    {
      "success": false,
      "orderId": null,
      "orderNumber": null,
      "externalId": "EXT-ORD-002",
      "recordIndex": 1,
      "errors": ["AccountId is required", "EffectiveDate is required"]
    },
    {
      "success": true,
      "orderId": "8015g00000ZZZZZZ",
      "orderNumber": "00000125",
      "externalId": "EXT-ORD-003",
      "recordIndex": 2,
      "errors": []
    }
  ],
  "errors": []
}
```

#### Exceeds Limit (HTTP 413)
```json
{
  "success": false,
  "message": "Request exceeds maximum allowed records",
  "totalRecords": 50000,
  "successCount": 0,
  "failureCount": 0,
  "results": [],
  "errors": [
    "Maximum 10000 orders allowed per request. Received: 50000",
    "For larger volumes, split into multiple requests or use Bulk API 2.0"
  ]
}
```

## Status Codes

| Code | Description |
|------|-------------|
| 201 | Order(s) created successfully |
| 207 | Multi-Status - partial success in bulk operation |
| 400 | Bad request - validation error or invalid JSON |
| 401 | Unauthorized - invalid or missing access token |
| 413 | Payload Too Large - exceeds 10,000 record limit |
| 500 | Internal server error - database or system error |

## Validation Rules

### Required Field Validation
- `AccountId` must be provided and must be a valid Salesforce Account ID
- `EffectiveDate` must be provided in `YYYY-MM-DD` format
- `Status` must be provided and must be either `"Draft"` or `"Activated"`

### Business Rules
- `TotalAmount` cannot be negative if provided
- `Status` must match one of the valid Order status values

## Governor Limits & Best Practices

### Maximum Records Per Request
- **Single Request Limit**: 10,000 orders maximum
- **Recommended Batch Size**: 200-500 orders for optimal performance
- **For 50,000+ Records**: Split into multiple requests or use Salesforce Bulk API 2.0

### Performance Guidelines
| Volume | Recommendation |
|--------|----------------|
| 1-100 orders | Single bulk request |
| 100-1,000 orders | Single bulk request |
| 1,000-10,000 orders | Single bulk request (may take 30-60 seconds) |
| 10,000-50,000 orders | Split into 5-10 batches of ~5,000-10,000 each |
| 50,000+ orders | Use Salesforce Bulk API 2.0 for async processing |

### Bulk Operation Features
- **Partial Success**: Successfully creates valid orders even if some fail
- **Individual Tracking**: Each order result includes its array index
- **External ID Tracking**: Track orders via External_ID__c field
- **Detailed Errors**: Each failed order includes specific error messages

## cURL Examples

### Create Single Draft Order
```bash
curl -X POST https://your-instance.salesforce.com/services/apexrest/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "AccountId": "0015g00000XXXXXX",
    "EffectiveDate": "2026-05-25",
    "Status": "Draft",
    "External_ID__c": "EXT-ORD-12345",
    "TotalAmount": 1000.00,
    "Description": "Test Order from cURL"
  }'
```

### Create Bulk Orders
```bash
curl -X POST https://your-instance.salesforce.com/services/apexrest/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "orders": [
      {
        "AccountId": "0015g00000XXXXXX",
        "EffectiveDate": "2026-05-25",
        "Status": "Draft",
        "External_ID__c": "EXT-001",
        "TotalAmount": 1000.00
      },
      {
        "AccountId": "0015g00000YYYYYY",
        "EffectiveDate": "2026-05-26",
        "Status": "Draft",
        "External_ID__c": "EXT-002",
        "TotalAmount": 2000.00
      },
      {
        "AccountId": "0015g00000ZZZZZZ",
        "EffectiveDate": "2026-05-27",
        "Status": "Activated",
        "External_ID__c": "EXT-003",
        "TotalAmount": 1500.00
      }
    ]
  }'
```

### Create Order with Contract
```bash
curl -X POST https://your-instance.salesforce.com/services/apexrest/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "AccountId": "0015g00000XXXXXX",
    "ContractId": "8005g00000XXXXXX",
    "EffectiveDate": "2026-05-25",
    "Status": "Draft",
    "TotalAmount": 2500.00,
    "Type": "Renewal"
  }'
```

## Handling Large Volumes (50,000+ Records)

For volumes exceeding 10,000 records, implement a batching strategy:

### Option 1: Sequential Batching
```python
# Python example
import requests
import json

def create_orders_in_batches(orders, batch_size=5000):
    base_url = "https://your-instance.salesforce.com/services/apexrest/orders"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token}"
    }
    
    results = []
    for i in range(0, len(orders), batch_size):
        batch = orders[i:i + batch_size]
        payload = {"orders": batch}
        
        response = requests.post(base_url, 
                                headers=headers, 
                                data=json.dumps(payload))
        results.append(response.json())
        
        print(f"Batch {i//batch_size + 1}: {response.status_code}")
    
    return results

# Usage for 50,000 orders
all_results = create_orders_in_batches(my_50k_orders, batch_size=5000)
```

### Option 2: Parallel Batching (Faster)
```python
# Python example with concurrent requests
from concurrent.futures import ThreadPoolExecutor
import requests

def send_batch(batch, batch_num):
    response = requests.post(
        "https://your-instance.salesforce.com/services/apexrest/orders",
        headers={"Content-Type": "application/json", 
                 "Authorization": f"Bearer {access_token}"},
        json={"orders": batch}
    )
    print(f"Batch {batch_num}: {response.status_code}")
    return response.json()

def create_orders_parallel(orders, batch_size=5000, max_workers=5):
    batches = [orders[i:i + batch_size] 
               for i in range(0, len(orders), batch_size)]
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        results = list(executor.map(
            lambda x: send_batch(x[1], x[0]), 
            enumerate(batches)
        ))
    
    return results

# Process 50,000 orders in ~10 batches with 5 concurrent requests
all_results = create_orders_parallel(my_50k_orders)
```

### Option 3: Salesforce Bulk API 2.0 (Best for 100K+ records)
For very large volumes, use Salesforce Bulk API 2.0 for async processing:
- Upload CSV file with order data
- Automatic batching and processing
- Query job status asynchronously
- Download results when complete

## Integration Notes

### Authentication Setup
1. Create a Connected App in Salesforce
2. Enable OAuth Settings
3. Set appropriate OAuth Scopes (api, refresh_token, offline_access)
4. Use OAuth 2.0 flow to obtain access token

### Error Handling Best Practices

#### Single Order Requests
- Check the `success` field in the response
- Log the `errors` array for debugging
- Implement retry logic for 500-series errors
- Handle 401 errors by refreshing the access token

#### Bulk Order Requests
- Check overall `success` field and status code
- For 207 (partial success), iterate through `results` array
- Retry failed orders from `results` where `success: false`
- Log `recordIndex` and `externalId` for tracking
- Consider splitting large batches if consistent timeouts occur

Example error handling:
```python
response = requests.post(url, headers=headers, json=payload)
data = response.json()

if response.status_code == 201:
    # Full success
    print(f"Created {data['successCount']} orders")
elif response.status_code == 207:
    # Partial success - retry failures
    failed_orders = [r for r in data['results'] if not r['success']]
    print(f"Success: {data['successCount']}, Failed: {data['failureCount']}")
    # Retry failed orders
elif response.status_code == 413:
    # Split into smaller batches
    print("Batch too large, splitting...")
else:
    # Handle other errors
    print(f"Error: {data['message']}")
```

### Rate Limits & Concurrency
- Standard Salesforce API rate limits apply (varies by edition)
- **Concurrent Requests**: Max 25 concurrent API calls per org
- **Daily API Limits**: Check your Salesforce edition limits
- For high volumes, use parallel batching (5-10 concurrent requests)
- Implement exponential backoff for rate limit errors
- Monitor API usage in Salesforce Setup → System Overview

### Security Considerations
- Store access tokens securely
- Use HTTPS for all API calls
- Rotate credentials regularly
- Implement IP restrictions on the Connected App if possible

## Testing

### Run Apex Tests
```bash
# Run all Order REST tests
sf apex run test --class-names OrderRestResourceTest,OrderRestResourceBulkTest --result-format human --code-coverage
```

### Expected Test Coverage

**OrderRestResourceTest** (Single order operations):
- Successful order creation
- Missing required fields validation
- Invalid field values validation
- JSON parsing errors
- Multiple validation errors
- Optional fields handling

**OrderRestResourceBulkTest** (Bulk operations):
- Bulk success with 5 orders
- Bulk success with 100 orders
- Partial success scenarios
- All failures scenario
- Empty orders array
- Exceeds 10,000 limit
- Single order still works after bulk implementation

## Support

For issues or questions:
- Review Salesforce debug logs for detailed error information
- Check field-level security and object permissions
- Verify the Connected App configuration
- Ensure the integration user has appropriate permissions

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| HTTP 413 error | Request exceeds 10,000 records | Split into smaller batches |
| Timeout on large batches | Processing too many records | Reduce batch size to 500-2000 |
| Partial success with "Unable to lock row" | Record locking conflicts | Implement retry logic with exponential backoff |
| "AccountId is required" error | Missing required field | Validate data before sending |
| HTTP 401 | Expired access token | Refresh OAuth token |

### Debug Checklist
1. ✅ Validate JSON format before sending
2. ✅ Check all required fields are present
3. ✅ Verify Account IDs exist in target org
4. ✅ Confirm batch size is under 10,000
5. ✅ Review Salesforce debug logs for DML errors
6. ✅ Check API limits in System Overview

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | 2026-05-25 | Added bulk order support (up to 10,000), partial success handling, governor limit protection |
| 1.0 | 2026-05-25 | Initial release with POST endpoint for single order creation |
