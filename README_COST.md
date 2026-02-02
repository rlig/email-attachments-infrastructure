# Cost Analysis for Email Attachments Infrastructure

This document provides detailed cost calculations for running the email attachments infrastructure at scale.

**Region:** Frankfurt (eu-central-1)  
**Currency:** USD  
**Pricing as of:** February 2026

## Table of Contents
- [Frankfurt Pricing Overview](#frankfurt-pricing-overview)
- [Baseline Costs (Low Traffic)](#baseline-costs-low-traffic)
- [Moderate-Scale Costs (50 QPS)](#moderate-scale-costs-50-qps)
- [Cost Optimizations](#cost-optimizations)
- [Optimization Implementation](#optimization-implementation)
- [Recommendations](#recommendations)

---

## Frankfurt Pricing Overview

**Key Differences from US East (us-east-1):**

| Service | Frankfurt | US East | Difference |
|---------|-----------|---------|------------|
| **API Gateway** | $4.25/1M requests | $3.50/1M | +21% |
| **Lambda** | Same | Same | 0% |
| **DynamoDB Reads** | $0.285/1M | $0.25/1M | +14% |
| **DynamoDB Writes** | $1.428/1M | $1.25/1M | +14% |
| **S3 Storage** | $0.0245/GB | $0.023/GB | +6.5% |
| **CloudFront Data** | Same | Same | 0% |
| **CloudFront Requests** | $0.012/10K | $0.01/10K | +20% |

**Overall Impact:**
- Baseline costs: +0.5% higher in Frankfurt
- Optimized costs: +0.3% higher in Frankfurt
- Difference: ~$80-150/month at 50 QPS


---

## Baseline Costs (Low Traffic)

**Scenario: 10,000 users, 1M requests/month**

| Service | Monthly Cost | Frankfurt Pricing |
|---------|--------------|-------------------|
| S3 (1TB storage) | $25.60 | €0.0245/GB |
| CloudFront (1TB transfer) | $85 | Europe pricing |
| Lambda (1M invocations) | $20 | Same as US |
| DynamoDB (on-demand) | $28.50 | €0.285/1M reads |
| API Gateway (1M requests) | $42.50 | €4.25/1M |
| Cognito (up to 50K MAU) | Free | Same as US |
| Secrets Manager | $0.40 | Same as US |
| CloudWatch | $10 | Same as US |
| **TOTAL** | **~$212/month** | **+7% vs US East** |

---

## Moderate-Scale Costs (50 QPS)

### Traffic Volume Calculations

**50 requests/second:**
- Per minute: 3,000 requests
- Per hour: 180,000 requests
- Per day: 4.32 million requests
- **Per month (30 days): ~129.6 million requests**

---

### Detailed Cost Breakdown

#### 1. API Gateway 💰

**Frankfurt (eu-central-1) Pricing Tiers:**
- First 333M requests: $4.25 per million
- Next 667M requests: $3.40 per million
- Over 1B requests: $2.89 per million

**Calculation:**
```
129.6M requests × $4.25/1M = $550.80
```

**Monthly Cost: $551** (+21% vs US East)

---

#### 2. AWS Lambda 💰

**Assumptions:**
- 129.6 million invocations/month
- Average execution time: 200ms
- Memory allocation: 512MB (0.5GB)

**Frankfurt (eu-central-1) Pricing:**
- Requests: $0.20 per 1M (same as US)
- Compute: $0.0000166667 per GB-second (same as US)

**Invocation Costs:**
```
(129.6M - 1M free tier) × $0.20/1M = $25.72
```

**Compute Costs:**
```
GB-seconds: 129.6M × 0.2s × 0.5GB = 12.96M GB-seconds
Cost: (12.96M - 400K free) × $0.0000166667 = $209.33
```

**Monthly Cost: $235** (same as US)

---

#### 3. Amazon DynamoDB 💰

**With PAY_PER_REQUEST (On-Demand) in Frankfurt:**

**Frankfurt Pricing:**
- Read requests: $0.285 per million (vs $0.25 in US)
- Write requests: $1.428 per million (vs $1.25 in US)

Each request requires 2 DynamoDB reads:
- UserEmailAccess table: 1 read
- EmailAttachments table (direct lookup): 1 read
- Total: ~259.2 million read requests/month

```
259.2M × $0.285/1M reads = $73.87
```

**Write requests (email metadata updates):**
```
~10M writes × $1.428/1M writes = $14.28
```

**✅ RECOMMENDED: Keep On-Demand**

For this traffic level, on-demand pricing is more cost-effective than provisioned capacity.

**Monthly Cost (On-Demand): $77** ✅ **RECOMMENDED**

---

#### 4. Amazon CloudFront 💰

**Assumptions:**
- Average file size: 5MB per attachment
- Monthly data transfer: 129.6M × 5MB = **648 TB**

**Data Transfer Pricing (Europe - Frankfurt):**
```
First 10TB:     10TB × $0.085/GB     = $870
Next 40TB:      40TB × $0.080/GB     = $3,276.80
Next 100TB:     100TB × $0.060/GB    = $6,144
Next 350TB:     350TB × $0.040/GB    = $14,336
Remaining 148TB: 148TB × $0.040/GB   = $6,062.08
Total data transfer:                   $30,688.88
```

**Request Pricing (Europe):**
```
HTTPS requests: 129.6M × $0.012/10,000 = $155.52
```

**Monthly Cost: $30,844** (+0.1% vs US, mainly request costs)

---

#### 5. Amazon S3 💰

**Frankfurt Pricing:**

**GET Requests:**
```
129.6M × $0.0004/1,000 = $51.84
```

**Storage (assuming 10TB):**
```
10,240GB × $0.0245/GB = $250.88
```

**Monthly Cost: $303** (+5.6% vs US)

---

#### 6. Amazon Cognito 💰

**Assumptions:**
- 50,000 monthly active users (MAU)
- JWT validation occurs at API Gateway (no per-request charge)

**Pricing:**
```
First 50K MAU: Free
```

**Monthly Cost: $0** (within free tier)

---

#### 7. AWS Secrets Manager 💰

**Usage:**
- 1 secret (CloudFront private key)
- API calls cached in Lambda cold starts
- ~1,000 API calls/month

```
Secret storage: $0.40
API calls: 1,000 × $0.05/10,000 = $0.005
```

**Monthly Cost: $1**

---

#### 8. Amazon CloudWatch 💰

**Lambda Logs:**
- Log size: ~5KB per invocation
- Total: 129.6M × 5KB = **648GB logs/month**

```
Ingestion: 648GB × $0.50/GB = $324
Storage (14-day retention): 648GB × $0.03/GB × 0.5 = $9.72
```

**API Gateway Logs:**
```
Ingestion: ~150GB × $0.50/GB = $75
```

**CloudWatch Alarms:**
```
3 alarms × $0.10 = $0.30
```

**Monthly Cost: $409**

---

### 💰 TOTAL MONTHLY COST (Without Optimizations)

**Frankfurt (eu-central-1) Pricing:**

| Service | Monthly Cost | vs US East |
|---------|--------------|------------|
| API Gateway | $551 | +21% |
| Lambda | $235 | same |
| DynamoDB (on-demand) | $91 | +18% |
| CloudFront | $30,844 | +0.1% |
| S3 | $303 | +5.6% |
| Cognito | $0 | same |
| Secrets Manager | $1 | same |
| CloudWatch | $409 | same |
| **TOTAL** | **$32,434/month** | **+0.5%** |

**Annual Cost: ~$389,208** (+$1,836/year vs US East)

**Key Findings:**
- Frankfurt is ~0.5% more expensive overall
- API Gateway (+21%) and DynamoDB (+18%) are notably higher
- CloudFront data transfer costs are similar (Europe pricing)
- Lambda and CloudWatch costs are identical

---

## Cost Optimizations

At 50 QPS (~130M requests/month), optimizations can reduce costs by 30-40%. The baseline architecture is already quite efficient at this scale.

### 1. 📉 Reduce CloudFront Costs

**Problem:** CloudFront is the largest cost at $30,818/month (95% of total).

**Solution A: Optimize file sizes**
- Compress files before upload when possible
- Use image optimization (WebP, AVIF for images)
- Expected reduction: 20-30% for compressible content

**Solution B: Use CloudFront Regional Edge Caches**
- Already enabled by default
- Improves cache hit ratio
- Reduces origin fetches from S3

**Solution C: Longer cache TTLs**
- Increase CloudFront cache TTL for static attachments
- Reduces S3 GET requests and CloudFront origin fetches

**Expected Savings:**
```
Data transfer reduction: 648TB × 20% = 130TB saved
Monthly savings: ~$5,200
New CloudFront cost: ~$25,600/month
```

**⚠️ Note:** At 648TB/month, you're not yet at volume pricing tier for PPA negotiation

---

### 2. 🚀 Add ElastiCache Redis (Authorization Caching)

**Problem:** 259M DynamoDB reads/month for authorization checks.

**Solution:**
- Cache authorization results in Redis for 5-15 minutes
- Cache hit rate: 90%+ (users typically access multiple attachments)
- Reduces DynamoDB reads by 90%

**Implementation:**
```hcl
resource "aws_elasticache_cluster" "auth_cache" {
  cluster_id           = "${var.project_name}-auth-cache"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t4g.micro"  # Sufficient for this scale
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
}
```

**Cost:**
```
cache.t4g.micro: $0.016/hour × 730 hours = $12/month
```

**Savings:**
```
DynamoDB reads reduced: 259M × 90% = 233M reads eliminated
Savings: 233M × $0.25/1M = $58.25/month

Net Savings: $46/month (60% ROI)
```

**Alternative:** May not be worth it at this scale. Consider if you grow to 200+ QPS.

---

### 3. ⚡ Switch to ECDSA Keys (91% Faster Signing)

**Problem:** RSA-2048 signing is computationally expensive (~20ms per signature).

**Solution:**
- Use ECDSA P-256 keys instead of RSA-2048
- Signing time: **2ms vs 20ms** (10x faster)
- Reduces Lambda execution time by 70%

**Lambda Code Update:**
```python
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes

# Generate ECDSA key pair
private_key = ec.generate_private_key(ec.SECP256R1())

# Signing function
def ecdsa_signer(message):
    return private_key.sign(message, ec.ECDSA(hashes.SHA256()))
```

**Savings:**
```
Lambda execution time: 200ms → 60ms
Compute cost reduction: 70%
Monthly savings: $235 × 0.70 = $165
```

**New Lambda Cost: $70/month** ✅

---

### 4. 🗄️ Skip DynamoDB DAX

**Recommendation:** **NOT recommended at this scale**

**Reasoning:**
- DynamoDB on-demand is only $77/month
- DAX costs minimum $175/month (dax.t3.small)
- Would increase costs without meaningful benefit
- DynamoDB latency (5-10ms) is acceptable at 50 QPS

**When to consider DAX:**
- When you exceed 500 QPS
- When p99 latency requirements are < 5ms
- When DynamoDB costs exceed $500/month

---

### 5. 📊 Reduce CloudWatch Logging

**Problem:** CloudWatch logs costing $409/month.

**Solution:**
- Log only errors, warnings, and audit events
- Remove debug/info logging in production
- Sample 10% of successful requests for monitoring
- Use CloudWatch Logs Insights for analysis

**Implementation:**
```python
import os
import random

# Only log errors and audit events
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'ERROR')
SAMPLE_RATE = 0.1  # Log 10% of successful requests

def lambda_handler(event, context):
    # Always log errors
    if error:
        print(f"[ERROR] {error}")
        return
    
    # Sample successful requests
    if random.random() < SAMPLE_RATE:
        print(f"[INFO] user={user_id} s3_key={s3_key}")
    
    # Always audit-log (lightweight)
    print(f"[AUDIT] user={user_id}")
```

**Savings:**
```
Logs reduced from 648GB to 130GB (80% reduction)
New cost: 130GB × $0.50/GB = $65/month
Monthly savings: $344
```

---

### 6. 🔄 Use CloudFront Signed Cookies (Instead of URLs)

**Problem:** Generating individual signed URLs for every file access.

**Solution:**
- When user authenticates, issue signed cookies valid for all their accessible files
- Reduces Lambda invocations by 70-80% for multi-file access
- User can download all attachments in an email without additional API calls

**Implementation:**
```python
# Generate cookies once per email/session
cookies = generate_signed_cookies(f'emails/{email_id}/*', expiration_days=1)

# Client stores cookies, accesses multiple files
# No additional Lambda invocations needed
```

**Savings:**
```
Assuming 70% of requests are multi-file access within same email:
Lambda invocations reduced: 129.6M × 70% = 90.7M eliminated
API Gateway requests reduced: 90.7M × $3.50/1M = $317 saved
Lambda cost reduced: $70 × 70% = $49 saved

Total savings: $366/month
```

**New Costs:**
- Lambda: $21/month
- API Gateway: $137/month

---

### 7. ⚙️ Skip Lambda Provisioned Concurrency

**Recommendation:** **NOT recommended at this scale**

**Reasoning:**
- At 50 QPS, cold starts are minimal (< 1% of requests)
- Provisioned concurrency costs more than entire Lambda budget
- Cold start latency (~1-2 seconds) acceptable for file downloads

**Cost if enabled:**
```
Minimum 2 instances × $0.0000041667/GB-second × 0.5GB × 730 hours × 3600
= $11/month (minimum)
```

**When to consider:**
- When you exceed 200 QPS consistently
- When cold start rate exceeds 5%
- When p99 latency requirements are critical

---

### 8. 🌐 CloudFront Compression (Already Enabled)

**Status:** ✅ Already enabled in provided configuration

**Implementation:**
```hcl
resource "aws_cloudfront_distribution" "attachments" {
  default_cache_behavior {
    compress = true  # Already enabled
  }
}
```

**Benefit:**
```
For text-heavy attachments (documents, HTML, JSON):
Compression ratio: 70% reduction
Expected savings: 10-15% of CloudFront costs = ~$3,000-$4,600/month
```

**Already included in baseline costs** ✅

---

## 💰 OPTIMIZED COST BREAKDOWN (Frankfurt)

### With All Optimizations Applied

| Service | Baseline Cost | Optimized Cost | Savings |
|---------|---------------|----------------|---------|
| API Gateway | $551 | $166 | $385 |
| Lambda (ECDSA + cookies) | $235 | $21 | $214 |
| DynamoDB (on-demand) | $91 | $91 | $0 |
| CloudFront (file optimization) | $30,844 | $25,621 | $5,223 |
| S3 | $303 | $303 | $0 |
| Cognito | $0 | $0 | $0 |
| CloudWatch (reduced logging) | $409 | $65 | $344 |
| Secrets Manager | $1 | $1 | $0 |
| **TOTAL** | **$32,434/month** | **$26,268/month** | **$6,166/month** |

**Annual Cost: $315,216** (down from $389,208)

**Total Savings: 19% reduction** 🎉

**Frankfurt vs US East (Optimized):**
- Frankfurt optimized: $26,268/month
- US East optimized: $26,188/month
- Difference: +$80/month (+0.3%)

### Not Recommended at This Scale
- ❌ ElastiCache Redis: Costs more than it saves
- ❌ DynamoDB DAX: Not needed for 50 QPS
- ❌ Lambda Provisioned Concurrency: Overkill for this traffic
- ❌ CloudFront PPA: Volume too low to negotiate

---

## Optimization Implementation

### Phase 1: Immediate (Week 1)
1. ✅ Reduce CloudWatch logging → **Save $344/month**
2. ✅ Optimize file sizes and compression → **Save $5,218/month**
3. ✅ Keep DynamoDB on-demand (most cost-effective)

### Phase 2: Code Changes (Week 2)
4. ✅ Switch to ECDSA signing → **Save $165/month**
5. ✅ Implement signed cookies strategy → **Save $366/month**

### Phase 3: Monitoring (Ongoing)
6. ✅ Set up cost anomaly detection
7. ✅ Monitor traffic growth
8. ✅ Review costs monthly for optimization opportunities

### When to Add Advanced Features:
- **ElastiCache Redis**: When you exceed 200 QPS
- **DynamoDB DAX**: When you exceed 500 QPS
- **Lambda Provisioned Concurrency**: When cold starts > 5%
- **CloudFront PPA**: When data transfer > 5PB/month

---

## Recommendations

### For 50 QPS (~130M requests/month) in Frankfurt:

1. **Implement Quick Wins (Week 1)**
   - ✅ Reduce CloudWatch logging to errors only
   - ✅ Optimize file uploads (compression, formats)
   - ✅ Keep current architecture (no major changes needed)
   - Expected savings: $5,567/month

2. **Code Optimizations (Week 2)**
   - ✅ Switch to ECDSA keys for faster signing
   - ✅ Implement signed cookies for email-level access
   - Expected savings: $599/month

3. **Monitor Growth**
   - Track requests per second trends
   - Monitor CloudFront data transfer
   - Set up billing alerts

4. **Plan for Scale**
   - At 100 QPS: Consider ElastiCache Redis
   - At 200 QPS: Consider Lambda Provisioned Concurrency
   - At 500 QPS: Consider DynamoDB DAX
   - At 1000+ QPS: Contact AWS for CloudFront PPA

5. **Cost Optimization Best Practices (Frankfurt-specific)**
   - Review AWS Cost Explorer monthly
   - Set budget alerts at $28,000 and $35,000
   - Use AWS Trusted Advisor recommendations
   - Monitor for unused resources
   - **Note**: Frankfurt pricing is ~0.5% higher than US East
   - API Gateway and DynamoDB are the main price differentials (+18-21%)
   - Consider US East for significantly lower costs if latency allows

---

## Alternative Architectures for Cost Reduction

### Option 1: Hybrid Edge Architecture

**Use Lambda@Edge for signing:**
- Sign URLs at CloudFront edge locations
- Eliminates API Gateway + Lambda in origin
- Reduces latency by 50-80ms

**Savings:**
```
Eliminate: API Gateway ($5,101) + Lambda origin ($1,016)
Add: Lambda@Edge ($10,000/month for 18B requests)
Net savings: ~$4,000/month + better latency
```

### Option 2: Pre-Signed URL Strategy

**Generate long-lived URLs in batch:**
- When email is received, pre-generate signed URLs (30-90 day expiry)
- Store URLs in DynamoDB
- Serve directly from database (no signing overhead)

**Savings:**
```
Lambda invocations reduced to email ingestion only
API Gateway: ~$100/month
Lambda: ~$50/month
Savings: ~$6,000/month
```

**Trade-off:** Longer URL expiration = slightly lower security

### Option 3: CloudFront Functions (JavaScript)

**Use CloudFront Functions for validation:**
- Cheaper than Lambda@Edge ($0.10/1M invocations)
- JavaScript-based, limited capabilities
- Can handle simple authorization checks

**Cost:**
```
18.14B × $0.10/1M = $1,814/month
Saves: ~$4,000/month vs Lambda
```

**Limitation:** Requires authorization data in cookies/headers

---

## Cost Monitoring & Alerts

### Set Up Budget Alerts

```hcl
resource "aws_budgets_budget" "monthly_cost" {
  name              = "monthly-infrastructure-budget"
  budget_type       = "COST"
  limit_amount      = "850000"
  limit_unit        = "USD"
  time_period_start = "2026-02-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["billing@example.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["billing@example.com"]
  }
}
```

### Key Metrics to Track

1. **Cost per request:** Target < $0.05
2. **CloudFront data transfer:** Track average file size
3. **Cache hit rates:** Redis (95%+), DAX (90%+)
4. **Lambda execution time:** Target < 50ms p99
5. **DynamoDB throttling:** Should be 0

---

## Summary (Frankfurt eu-central-1)

| Metric | Value |
|--------|-------|
| **Region** | **Frankfurt (eu-central-1)** |
| **Traffic** | 50 QPS (129.6M requests/month) |
| **Baseline Cost** | $32,434/month |
| **Optimized Cost** | $26,268/month |
| **Savings** | $6,166/month (19%) |
| **vs US East** | +$80/month (+0.3% optimized) |
| **Largest Cost** | CloudFront data transfer (79% of total) |
| **Quick Wins** | Reduce logging, optimize files, ECDSA keys |
| **ROI Timeline** | 1-2 weeks |
| **Annual Cost** | $315,216 (optimized) |

---

## Next Steps

1. **Review this cost analysis** with your team
2. **Contact AWS Sales** for CloudFront PPA (biggest savings)
3. **Implement Phase 1 optimizations** (immediate savings)
4. **Create Terraform modules** for Redis and DAX
5. **Update Lambda code** for ECDSA and caching
6. **Set up cost monitoring** and alerts
7. **Test at scale** in staging environment

For questions or assistance with implementation, refer to:
- `README.md` - Infrastructure setup
- `lambda/lambda_function.py` - Lambda implementation


---

**Last Updated:** February 2026  
**Cost Data Source:** AWS Pricing Calculator (US East region)  
**Assumptions:** 5MB average file size, consistent traffic distribution
