import 'dart:convert';

// Generated from the authoritative backend template catalogue.
final administrativeTemplates =
    (jsonDecode(r'''[
  {
    "id": "advance",
    "prefix": "TU",
    "names": [
      "Phiếu tạm ứng",
      "Advance request",
      "ໃບຂໍເບີກລ່ວງໜ້າ"
    ],
    "permission": "finance.approve",
    "fields": [
      {
        "key": "amount",
        "label": [
          "Số tiền đề nghị",
          "Requested amount",
          "ຈຳນວນເງິນ"
        ],
        "type": "money",
        "required": true
      },
      {
        "key": "currency",
        "label": [
          "Tiền tệ",
          "Currency",
          "ສະກຸນເງິນ"
        ],
        "type": "currency",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "advanceSettlement",
    "prefix": "HU",
    "names": [
      "Phiếu hoàn ứng",
      "Advance settlement",
      "ໃບຊຳລະເງິນລ່ວງໜ້າ"
    ],
    "permission": "finance.approve",
    "fields": [
      {
        "key": "reference",
        "label": [
          "Mã phiếu tạm ứng",
          "Advance code",
          "ລະຫັດໃບລ່ວງໜ້າ"
        ],
        "type": "text",
        "required": true
      },
      {
        "key": "received",
        "label": [
          "Số tiền nhận đề nghị đối chiếu",
          "Received amount to reconcile",
          "ເງິນຮັບ"
        ],
        "type": "money",
        "required": true
      },
      {
        "key": "spent",
        "label": [
          "Số đã chi",
          "Spent amount",
          "ເງິນຈ່າຍ"
        ],
        "type": "money",
        "required": true
      },
      {
        "key": "currency",
        "label": [
          "Tiền tệ",
          "Currency",
          "ສະກຸນເງິນ"
        ],
        "type": "currency",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "payment",
    "prefix": "TT",
    "names": [
      "Đề nghị thanh toán",
      "Payment request",
      "ໃບຂໍຊຳລະ"
    ],
    "permission": "finance.approve",
    "fields": [
      {
        "key": "amount",
        "label": [
          "Số tiền đề nghị",
          "Requested amount",
          "ຈຳນວນເງິນ"
        ],
        "type": "money",
        "required": true
      },
      {
        "key": "currency",
        "label": [
          "Tiền tệ",
          "Currency",
          "ສະກຸນເງິນ"
        ],
        "type": "currency",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "disbursement",
    "prefix": "DC",
    "names": [
      "Đề nghị chi",
      "Disbursement request",
      "ໃບຂໍຈ່າຍ"
    ],
    "permission": "finance.approve",
    "fields": [
      {
        "key": "amount",
        "label": [
          "Số tiền đề nghị",
          "Requested amount",
          "ຈຳນວນເງິນ"
        ],
        "type": "money",
        "required": true
      },
      {
        "key": "currency",
        "label": [
          "Tiền tệ",
          "Currency",
          "ສະກຸນເງິນ"
        ],
        "type": "currency",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "annualLeave",
    "prefix": "NP",
    "names": [
      "Đơn nghỉ phép",
      "Annual leave",
      "ໃບຂໍລາພັກ"
    ],
    "permission": "attendance.verify",
    "fields": [
      {
        "key": "start",
        "label": [
          "Từ ngày",
          "From",
          "ແຕ່ວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "end",
        "label": [
          "Đến ngày",
          "To",
          "ເຖິງວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "sickLeave",
    "prefix": "NO",
    "names": [
      "Đơn nghỉ ốm",
      "Sick leave",
      "ໃບຂໍລາປ່ວຍ"
    ],
    "permission": "attendance.verify",
    "fields": [
      {
        "key": "start",
        "label": [
          "Từ ngày",
          "From",
          "ແຕ່ວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "end",
        "label": [
          "Đến ngày",
          "To",
          "ເຖິງວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "unpaidLeave",
    "prefix": "NK",
    "names": [
      "Đơn nghỉ không lương",
      "Unpaid leave",
      "ໃບຂໍລາບໍ່ຮັບເງິນ"
    ],
    "permission": "attendance.verify",
    "fields": [
      {
        "key": "start",
        "label": [
          "Từ ngày",
          "From",
          "ແຕ່ວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "end",
        "label": [
          "Đến ngày",
          "To",
          "ເຖິງວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "overtime",
    "prefix": "TC",
    "names": [
      "Đăng ký tăng ca",
      "Overtime request",
      "ໃບຂໍເຮັດວຽກລ່ວງເວລາ"
    ],
    "permission": "attendance.verify",
    "fields": [
      {
        "key": "start",
        "label": [
          "Từ ngày",
          "From",
          "ແຕ່ວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "end",
        "label": [
          "Đến ngày",
          "To",
          "ເຖິງວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "hours",
        "label": [
          "Số giờ",
          "Hours",
          "ຊົ່ວໂມງ"
        ],
        "type": "number",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "attendanceCorrection",
    "prefix": "CC",
    "names": [
      "Điều chỉnh chấm công",
      "Attendance correction",
      "ໃບແກ້ໄຂວັນວຽກ"
    ],
    "permission": "attendance.verify",
    "fields": [
      {
        "key": "start",
        "label": [
          "Từ ngày",
          "From",
          "ແຕ່ວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "end",
        "label": [
          "Đến ngày",
          "To",
          "ເຖິງວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "businessTrip",
    "prefix": "CT",
    "names": [
      "Đề nghị công tác",
      "Business trip",
      "ໃບຂໍໄປວຽກ"
    ],
    "permission": "office.edit",
    "fields": [
      {
        "key": "start",
        "label": [
          "Từ ngày",
          "From",
          "ແຕ່ວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "end",
        "label": [
          "Đến ngày",
          "To",
          "ເຖິງວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "tripPlan",
    "prefix": "KC",
    "names": [
      "Kế hoạch công tác",
      "Trip plan",
      "ແຜນໄປວຽກ"
    ],
    "permission": "office.edit",
    "fields": [
      {
        "key": "start",
        "label": [
          "Từ ngày",
          "From",
          "ແຕ່ວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "end",
        "label": [
          "Đến ngày",
          "To",
          "ເຖິງວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "tripReport",
    "prefix": "BC",
    "names": [
      "Báo cáo công tác",
      "Trip report",
      "ລາຍງານໄປວຽກ"
    ],
    "permission": "office.edit",
    "fields": [
      {
        "key": "start",
        "label": [
          "Từ ngày",
          "From",
          "ແຕ່ວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "end",
        "label": [
          "Đến ngày",
          "To",
          "ເຖິງວັນທີ"
        ],
        "type": "date",
        "required": true
      },
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "purchase",
    "prefix": "MH",
    "names": [
      "Đề nghị mua hàng",
      "Purchase request",
      "ໃບຂໍຊື້"
    ],
    "permission": "purchase.approve",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      },
      {
        "key": "amount",
        "label": [
          "Số tiền đề nghị",
          "Requested amount",
          "ຈຳນວນເງິນ"
        ],
        "type": "money",
        "required": true
      },
      {
        "key": "currency",
        "label": [
          "Tiền tệ",
          "Currency",
          "ສະກຸນເງິນ"
        ],
        "type": "currency",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "materialIssue",
    "prefix": "VT",
    "names": [
      "Đề nghị cấp vật tư",
      "Material request",
      "ໃບຂໍວັດສະດຸ"
    ],
    "permission": "inventory.approve",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "tools",
    "prefix": "DCU",
    "names": [
      "Đề nghị cấp công cụ",
      "Tools request",
      "ໃບຂໍເຄື່ອງມື"
    ],
    "permission": "inventory.approve",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "protectiveEquipment",
    "prefix": "BH",
    "names": [
      "Đề nghị cấp bảo hộ",
      "Protective equipment",
      "ໃບຂໍອຸປະກອນປ້ອງກັນ"
    ],
    "permission": "inventory.approve",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "assetHandover",
    "prefix": "BG",
    "names": [
      "Biên bản bàn giao tài sản",
      "Asset handover",
      "ໃບມອບຊັບສິນ"
    ],
    "permission": "office.edit",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "repair",
    "prefix": "SC",
    "names": [
      "Đề nghị sửa chữa",
      "Repair request",
      "ໃບຂໍສ້ອມແປງ"
    ],
    "permission": "machine.verify",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "proposal",
    "prefix": "DX",
    "names": [
      "Phiếu đề xuất",
      "Proposal",
      "ໃບສະເໜີ"
    ],
    "permission": "office.edit",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "workReport",
    "prefix": "CV",
    "names": [
      "Báo cáo công việc",
      "Work report",
      "ລາຍງານວຽກ"
    ],
    "permission": "office.edit",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "minutes",
    "prefix": "BB",
    "names": [
      "Biên bản",
      "Minutes",
      "ບົດບັນທຶກ"
    ],
    "permission": "office.edit",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  },
  {
    "id": "departmentSupport",
    "prefix": "HT",
    "names": [
      "Yêu cầu hỗ trợ phòng ban",
      "Department support",
      "ໃບຂໍຊ່ວຍເຫຼືອ"
    ],
    "permission": "office.edit",
    "fields": [
      {
        "key": "reason",
        "label": [
          "Lý do / nội dung",
          "Reason / details",
          "ເຫດຜົນ / ເນື້ອໃນ"
        ],
        "type": "multiline",
        "required": true
      }
    ],
    "version": 1
  }
]''')
            as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList(growable: false);
