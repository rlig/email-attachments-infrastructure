@echo off
echo ======================================
echo Cleaning Lambda Directory
echo ======================================
echo.

cd /d "%~dp0lambda"

echo Deleting installed Python packages...
if exist bin rmdir /s /q bin
if exist boto3 rmdir /s /q boto3
if exist botocore rmdir /s /q botocore
if exist dateutil rmdir /s /q dateutil
if exist jmespath rmdir /s /q jmespath
if exist pycparser rmdir /s /q pycparser
if exist s3transfer rmdir /s /q s3transfer
if exist urllib3 rmdir /s /q urllib3
if exist boto3-1.34.0.dist-info rmdir /s /q boto3-1.34.0.dist-info
if exist botocore-1.34.162.dist-info rmdir /s /q botocore-1.34.162.dist-info
if exist python_dateutil-2.9.0.post0.dist-info rmdir /s /q python_dateutil-2.9.0.post0.dist-info
if exist s3transfer-0.9.0.dist-info rmdir /s /q s3transfer-0.9.0.dist-info
if exist six-1.17.0.dist-info rmdir /s /q six-1.17.0.dist-info
if exist urllib3-2.6.3.dist-info rmdir /s /q urllib3-2.6.3.dist-info
if exist jmespath-1.1.0.dist-info rmdir /s /q jmespath-1.1.0.dist-info
if exist pycparser-3.0.dist-info rmdir /s /q pycparser-3.0.dist-info
if exist __pycache__ rmdir /s /q __pycache__
if exist six.py del six.py

echo.
echo ======================================
echo Lambda Directory Cleaned!
echo ======================================
echo.
echo Remaining files (should only be source code):
dir /b
echo.
echo Expected: lambda_function.py, authorization.py, requirements.txt
echo.

pause
