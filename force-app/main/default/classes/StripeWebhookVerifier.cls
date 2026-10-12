public without sharing class StripeWebhookVerifier {
    public static Boolean verifySignature(String payload, String sigHeader, String endpointSecret) {
        if (String.isBlank(sigHeader) || String.isBlank(payload) || String.isBlank(endpointSecret)) {
            return false;
        }

        Map<String, String> headerMap = new Map<String, String>();
        for (String item : sigHeader.split(',')) {
            String[] kv = item.split('=');
            if (kv.size() == 2) headerMap.put(kv[0].trim(), kv[1].trim());
        }

        String timestamp = headerMap.get('t');
        String signature = headerMap.get('v1');
        if (timestamp == null || signature == null) return false;

        Long eventTime = Long.valueOf(timestamp);
        Long now = DateTime.now().getTime() / 1000;
        if (Math.abs(now - eventTime) > 300) return false; // Replay mitigation

        String payloadToSign = timestamp + '.' + payload;
        Blob hmac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payloadToSign), Blob.valueOf(endpointSecret));
        return EncodingUtil.convertToHex(hmac).equalsIgnoreCase(signature);
    }
}