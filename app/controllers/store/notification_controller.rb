def _xmlval(hash, key)
  if hash[key] == {}
    nil
  else
    hash[key]
  end
end


class Store::NotificationController < ApplicationController

  ## Google Checkout notification

  def gcheckout
    notification = XmlSimple.xml_in(request.raw_post, 'KeepRoot' => true, 'ForceArray' => false)

    notification_name = notification.keys[0]
    notification_data = notification[notification_name]

    case notification_name
    when 'new-order-notification'
      process_new_order_notification(notification_data)
      
    when 'charge-amount-notification'
      process_charge_amount_notification(notification_data)
    # Ignore the other notifications
#   when 'order-state-change-notification'
#   when 'risk-information-notification'
    end

    render_text ''
  end

  private
  def process_new_order_notification(n)
    order = Order.find(Integer(n['shopping-cart']['merchant-private-data']['order-id']))

    return if order == nil or order.payment_type != 'Google Checkout'
    
    ba = n['buyer-billing-address']

    words = ba['contact-name'].split(' ')
    order.first_name = words.shift
    order.last_name = words.join(' ')

    order.email = _xmlval(ba, 'email')
    if order.email == nil
      order.status = 'C'
      order.failure_reason = 'Did not get email from Google Checkout'
      order.finish_and_save()
      return
    end

    order.address1 = _xmlval(ba, 'address1')
    order.address2 = _xmlval(ba, 'address2')
    order.city     = _xmlval(ba, 'city')
    order.company  = _xmlval(ba, 'company-name')
    order.country  = _xmlval(ba, 'country-code')
    order.zipcode  = _xmlval(ba, 'postal-code')
    order.state    = _xmlval(ba, 'region')
    
    order.transaction_number = n['google-order-number']

    order.save()

    order.subscribe_to_list() if n['buyer-marketing-preferences']['email_allowed'] == 'true'

    order.send_to_google_add_merchant_order_number_command()
  end

  private
  def process_charge_amount_notification(n)
    order = Order.find_by_transaction_number_and_payment_type(n['google-order-number'], 'Google Checkout')

    return if order == nil or order.status == 'C'

    order.status = 'C'
    order.finish_and_save()
    OrderMailer.deliver_thankyou(order)

    order.send_to_google_deliver_order_command()
    order.send_to_google_archive_order_command()
  end
  
end
