public interface IPricingStrategy {
    Decimal calculateCharge(String meterType, Decimal quantity);
}